require_relative '../test_helper'
require 'digest/sha1'

module Wolverine
  class ScriptTest < MiniTest::Unit::TestCase
    CONTENT = "return 1"
    DIGEST = Digest::SHA1.hexdigest(CONTENT)

    def setup
      Wolverine::Script.any_instance.stubs(load_lua: CONTENT)
    end

    def script
      @script ||= Wolverine::Script.new('file1')
    end

    def test_compilation_error
      base = Pathname.new('/a/b/c/d')
      file = Pathname.new('/a/b/c/d/e/file1.lua')
      Wolverine.config.script_path = base
      begin
        script = Wolverine::Script.new(file)
        script.instance_variable_set("@content", "asdfasdfasdf+31f")
        script.instance_variable_set("@digest", "79437f5edda13f9c1669b978dd7a9066dd2059f1")
        script.call(Redis.new)
      rescue Wolverine::LuaError => e
        assert_equal "'=' expected near '+'", e.message
        assert_equal "/a/b/c/d/e/file1.lua:1", e.backtrace.first
        assert_match /script.rb/, e.backtrace[1]
      end
    end

    def test_runtime_error
      base = Pathname.new('/a/b/c/d')
      file = Pathname.new('/a/b/c/d/e/file1.lua')
      Wolverine.config.script_path = base
      begin
        script = Wolverine::Script.new(file)
        script.instance_variable_set("@content", "return nil > 3")
        script.instance_variable_set("@digest", "39437f5edda13f9c1669b978dd7a9066dd2059f1")
        script.call(Redis.new)
      rescue Wolverine::LuaError => e
        assert_equal "attempt to compare number with nil", e.message
        assert_equal "/a/b/c/d/e/file1.lua:1", e.backtrace.first
        assert_match /script.rb/, e.backtrace[1]
      end
    end

    def test_call_with_cache_hit
      tc = self
      redis = Class.new do
        define_method(:evalsha) do |digest, size, *args|
          tc.assert_equal DIGEST, digest
          tc.assert_equal 2, size
          tc.assert_equal [:a, :b], args
        end
      end
      script.call(redis.new, :a, :b)
    end

    def test_call_with_cache_miss
      tc = self
      redis = Class.new do
        define_method(:evalsha) do |*|
          raise "NOSCRIPT No matching script. Please use EVAL."
        end
        define_method(:eval) do |content, size, *args|
          tc.assert_equal CONTENT, content
          tc.assert_equal 2, size
          tc.assert_equal [:a, :b], args
        end
      end
      script.call(redis.new, :a, :b)
    end

  end
end
