require 'erb'
require 'shellwords'

module RSpec
  module Core
    # @private
    class ConfigurationOptions
      def initialize(args)
        @args = args.map {|a|
          a.sub("default_path", "default-path").sub("line_number",  "line-number")
        }
      end

      def configure(config)
        config.filter_manager = filter_manager

        process_options_into config
        load_formatters_into config
      end

      def options
        @options ||= (file_options << command_line_options << env_options).
          each {|opts|
            filter_manager.include opts.delete(:inclusion_filter) if opts.has_key?(:inclusion_filter)
            filter_manager.exclude opts.delete(:exclusion_filter) if opts.has_key?(:exclusion_filter)
          }.
          inject(:libs => [], :requires => []) {|h, opts|
            h.merge(opts) {|k, oldval, newval|
              [:libs, :requires].include?(k) ? oldval + newval : newval
            }
          }
      end

      def drb_argv
        DrbOptions.new(options, filter_manager).options
      end

      def filter_manager
        @filter_manager ||= RSpec::configuration.filter_manager
      end

    private

      UNFORCED_OPTIONS = [
        :requires, :profile, :drb, :libs, :files_or_directories_to_run,
        :line_numbers, :full_description, :full_backtrace, :tty
      ].to_set

      UNPROCESSABLE_OPTIONS = [:formatters].to_set

      def force?(key)
        !UNFORCED_OPTIONS.include?(key)
      end

      def order(keys)
        OPTIONS_ORDER.reverse.each do |key|
          keys.unshift(key) if keys.delete(key)
        end
        keys
      end

      OPTIONS_ORDER = [
        # load paths depend on nothing, but must be set before `requires`
        # to support load-path-relative requires.
        :libs,

        # `files_or_directories_to_run` uses `default_path` so it must be
        # set before it.
        :default_path,

        # must be set before `requires` to support checking `config.files_to_run`
        # from within `spec_helper.rb` when a `-rspec_helper` option is used.
        :files_or_directories_to_run,

        # In general, we want to require the specified files as early as possible.
        # The `--require` option is specifically intended to allow early requires.
        # For later requires, they can just put the require in their spec files, but
        # `--require` provides a unique opportunity for users to instruct RSpec to
        # load an extension file early for maximum flexibility.
        :requires
      ]

      def process_options_into(config)
        opts = options.reject { |k, _| UNPROCESSABLE_OPTIONS.include? k }

        order(opts.keys).each do |key|
          force?(key) ? config.force(key => opts[key]) : config.__send__("#{key}=", opts[key])
        end
      end

      def load_formatters_into(config)
        options[:formatters].each { |pair| config.add_formatter(*pair) } if options[:formatters]
      end

      def file_options
        custom_options_file ? [custom_options] : [global_options, project_options, local_options]
      end

      def env_options
        ENV["SPEC_OPTS"] ? Parser.parse(Shellwords.split(ENV["SPEC_OPTS"])) : {}
      end

      def command_line_options
        @command_line_options ||= Parser.parse(@args).merge :files_or_directories_to_run => @args
      end

      def custom_options
        options_from(custom_options_file)
      end

      def local_options
        @local_options ||= options_from(local_options_file)
      end

      def project_options
        @project_options ||= options_from(project_options_file)
      end

      def global_options
        @global_options ||= options_from(global_options_file)
      end

      def options_from(path)
        Parser.parse(args_from_options_file(path))
      end

      def args_from_options_file(path)
        return [] unless path && File.exist?(path)
        config_string = options_file_as_erb_string(path)
        FlatMap.flat_map(config_string.split(/\n+/), &:shellsplit)
      end

      def options_file_as_erb_string(path)
        ERB.new(File.read(path), nil, '-').result(binding)
      end

      def custom_options_file
        command_line_options[:custom_options_file]
      end

      def project_options_file
        ".rspec"
      end

      def local_options_file
        ".rspec-local"
      end

      def global_options_file
        begin
          File.join(File.expand_path("~"), ".rspec")
        rescue ArgumentError
          RSpec.warning "Unable to find ~/.rspec because the HOME environment variable is not set"
          nil
        end
      end
    end
  end
end
