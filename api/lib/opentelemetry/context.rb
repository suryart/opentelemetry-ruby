# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'opentelemetry/context/key'
require 'opentelemetry/context/propagation'

module OpenTelemetry
  # Manages context on a per-fiber basis
  class Context
    KEY = :__opentelemetry_context__
    EMPTY_ENTRIES = {}.freeze
    private_constant :KEY, :EMPTY_ENTRIES

    class << self
      # Returns a key used to index a value in a Context
      #
      # @param [String] name The key name
      # @return [Context::Key]
      def create_key(name)
        Key.new(name)
      end

      # Returns current context, which is never nil
      #
      # @return [Context]
      def current
        Thread.current[KEY] ||= ROOT
      end

      # @api private
      def current=(ctx)
        Thread.current[KEY] = ctx
      end

      # Returns a token to be used with the matching call to detach
      #
      # @param [Context] context The new context
      # @return [Integer] A token to be used when detaching
      def attach(context)
        prev = current
        self.current = context
        stack.push(prev)
        stack.size
      end

      # Restores the previous context, if a token is supplied it will
      # be used to check if the call to detach is balanced with
      # the original attach call. A warning is logged if the
      # calls are unbalanced.
      #
      # @param [Integer] token The token provided by the matching call to attach
      def detach(token = nil)
        OpenTelemetry.logger.warn 'Calls to detach should match corresponding calls to attach' if token && token != stack.size

        previous_context = stack.pop || ROOT
        self.current = previous_context
      end

      # Executes a block with ctx as the current context. It restores
      # the previous context upon exiting.
      #
      # @param [Context] ctx The context to be made active
      # @yield [context] Yields context to the block
      def with_current(ctx)
        prev = attach(ctx)
        yield ctx
      ensure
        detach(prev)
      end

      # Execute a block in a new context with key set to value. Restores the
      # previous context after the block executes.

      # @param [String] key The lookup key
      # @param [Object] value The object stored under key
      # @param [Callable] Block to execute in a new context
      # @yield [context, value] Yields the newly created context and value to
      #   the block
      def with_value(key, value)
        ctx = current.set_value(key, value)
        prev = attach(ctx)
        yield ctx, value
      ensure
        detach(prev)
      end

      # Execute a block in a new context where its values are merged with the
      # incoming values. Restores the previous context after the block executes.

      # @param [String] key The lookup key
      # @param [Hash] values Will be merged with values of the current context
      #  and returned in a new context
      # @param [Callable] Block to execute in a new context
      # @yield [context, values] Yields the newly created context and values
      #   to the block
      def with_values(values)
        ctx = current.set_values(values)
        prev = attach(ctx)
        yield ctx, values
      ensure
        detach(prev)
      end

      # Returns the value associated with key in the current context
      #
      # @param [String] key The lookup key
      def value(key)
        current.value(key)
      end

      def clear
        stack.clear
        self.current = ROOT
      end

      def empty
        new(EMPTY_ENTRIES)
      end

      private

      def stack
        @stack ||= []
      end
    end

    def initialize(entries)
      @entries = entries.freeze
    end

    # Returns the corresponding value (or nil) for key
    #
    # @param [Key] key The lookup key
    # @return [Object]
    def value(key)
      @entries[key]
    end

    alias [] value

    # Returns a new Context where entries contains the newly added key and value
    #
    # @param [Key] key The key to store this value under
    # @param [Object] value Object to be stored under key
    # @return [Context]
    def set_value(key, value)
      new_entries = @entries.dup
      new_entries[key] = value
      Context.new(new_entries)
    end

    # Returns a new Context with the current context's entries merged with the
    #   new entries
    #
    # @param [Hash] values The values to be merged with the current context's
    #   entries.
    # @param [Object] value Object to be stored under key
    # @return [Context]
    def set_values(values) # rubocop:disable Naming/AccessorMethodName:
      Context.new(@entries.merge(values))
    end

    ROOT = empty.freeze
  end
end
