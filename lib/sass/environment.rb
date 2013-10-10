require 'set'

module Sass
  # The abstract base class for lexical environments for SassScript.
  class BaseEnvironment
    class << self
      # Note: when updating this,
      # update sass/yard/inherited_hash.rb as well.
      def inherited_hash_accessor(name)
        inherited_hash_reader(name)
        inherited_hash_writer(name)
      end

      def inherited_hash_reader(name)
        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{name}(name)
            _#{name}(name.tr('_', '-'))
          end

          def _#{name}(name)
            (@#{name}s && @#{name}s[name]) || @parent && @parent._#{name}(name)
          end
          protected :_#{name}
        RUBY
      end

      def inherited_hash_writer(name)
        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def set_#{name}(name, value)
            name = name.tr('_', '-')
            @#{name}s[name] = value unless try_set_#{name}(name, value)
          end

          def try_set_#{name}(name, value)
            @#{name}s ||= {}
            if @#{name}s.include?(name)
              @#{name}s[name] = value
              true
            elsif @parent
              @parent.try_set_#{name}(name, value)
            else
              false
            end
          end
          protected :try_set_#{name}

          def set_local_#{name}(name, value)
            @#{name}s ||= {}
            @#{name}s[name.tr('_', '-')] = value
          end
        RUBY
      end
    end

    # The options passed to the Sass Engine.
    attr_reader :options

    attr_writer :caller
    attr_writer :content

    # variable
    # Script::Value
    inherited_hash_reader :var

    # mixin
    # Sass::Callable
    inherited_hash_reader :mixin

    # function
    # Sass::Callable
    inherited_hash_reader :function

    # @param options [{Symbol => Object}] The options hash. See
    #   {file:SASS_REFERENCE.md#sass_options the Sass options documentation}.
    # @param parent [Environment] See \{#parent}
    def initialize(parent = nil, options = nil)
      @parent = parent
      @options = options || (parent && parent.options) || {}
      @stack = Sass::Stack.new if @parent.nil?
    end

    # The environment of the caller of this environment's mixin or function.
    # @return {Environment?}
    def caller
      @caller || (@parent && @parent.caller)
    end

    # The content passed to this environment. This is naturally only set
    # for mixin body environments with content passed in.
    #
    # @return {[Array<Sass::Tree::Node>, Environment]?} The content nodes and
    #   the lexical environment of the content block.
    def content
      @content || (@parent && @parent.content)
    end

    # The selector for the current CSS rule, or nil if there is no
    # current CSS rule.
    #
    # @return [Selector::CommaSequence?] The current selector, with any
    #   nesting fully resolved.
    def selector
      return if @no_selector
      return @selector if @selector
      return @caller.selector if @caller
      return @parent.selector if @parent
      nil
    end

    def selector=(value)
      @selector = value
      @no_selector = false
    end

    # Mark this environment as having no selector information. Unlike setting
    # {#selector} to nil, this indicates that this environment should not
    # inherit its {#parent}'s or {#caller}'s selector.
    #
    # This will be overwritten if {#selector} is set.
    def no_selector!
      @selector = nil
      @no_selector = true
    end

    # The top-level Environment object.
    #
    # @return [Environment]
    def global_env
      @global_env ||= parent.nil? ? self : parent.global_env
    end

    # The import/mixin stack.
    #
    # @return [Sass::Stack]
    def stack
      @stack || global_env.stack
    end
  end

  # The lexical environment for SassScript.
  # This keeps track of variable, mixin, and function definitions.
  #
  # A new environment is created for each level of Sass nesting.
  # This allows variables to be lexically scoped.
  # The new environment refers to the environment in the upper scope,
  # so it has access to variables defined in enclosing scopes,
  # but new variables are defined locally.
  #
  # Environment also keeps track of the {Engine} options
  # so that they can be made available to {Sass::Script::Functions}.
  class Environment < BaseEnvironment
    # The enclosing environment,
    # or nil if this is the global environment.
    #
    # @return [Environment]
    attr_reader :parent

    # variable
    # Script::Value
    inherited_hash_writer :var

    # mixin
    # Sass::Callable
    inherited_hash_writer :mixin

    # function
    # Sass::Callable
    inherited_hash_writer :function
  end

  # A read-only wrapper for a lexical environment for SassScript.
  class ReadOnlyEnvironment < BaseEnvironment
    # The read-only environment of the caller of this environment's mixin or function.
    #
    # @see BaseEnvironment#caller
    # @return {ReadOnlyEnvironment}
    def caller
      return @caller if @caller
      env = super
      @caller ||= env.is_a?(ReadOnlyEnvironment) ? env : ReadOnlyEnvironment.new(env, env.options)
    end

    # The read-only content passed to this environment.
    #
    # @see BaseEnvironment#content
    # @return {ReadOnlyEnvironment}
    def content
      return @content if @content
      env = super
      @content ||= env.is_a?(ReadOnlyEnvironment) ? env : ReadOnlyEnvironment.new(env, env.options)
    end
  end
end
