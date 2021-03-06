require 'erb'
require 'fileutils'
require 'rubygems'
require 'active_support/inflector'

module RESTRack
  class Generator

    TEMPLATE = {
      :service                => 'loader.rb.erb',
      :rackup                 => 'config.ru.erb',
      :constants              => 'constants.yaml.erb',
      :controller             => 'controller.rb.erb',
      :descendant_controller  => 'descendant_controller.rb.erb',
      :hooks                  => 'hooks.rb.erb',
      :gemfile                => 'Gemfile.erb'
    }

    class << self

      # Generate controller file
      def generate_controller(name)
        template = get_template_for( :controller )
        resultant_string = template.result( get_binding_for_controller( name ) )
        File.open("#{base_dir}/controllers/#{name}_controller.rb", 'w') {|f| f.puts resultant_string }
        # Generate view folder for controller
        FileUtils.makedirs("#{base_dir}/views/#{name}")
      end

      # Generate controller file the descends from specified parent, to enable
      # grouping of controller types and/or overarching functionality.
      def generate_descendant_controller(name, parent)
        template = get_template_for( :descendant_controller )
        resultant_string = template.result( get_binding_for_descendant_controller( name, parent ) )
        File.open("#{base_dir}/controllers/#{name}_controller.rb", 'w') {|f| f.puts resultant_string }
        # Generate view folder for controller
        FileUtils.makedirs("#{base_dir}/views/#{name}")
      end

      # The guts for generating a new RESTRack service. The loader.rb template
      # will create a RESTRack::WebService or RESTRack::AsyncWebService based on
      # the value of @async.
      def generate_service(name)
        FileUtils.makedirs("#{name}/config")
        FileUtils.makedirs("#{name}/controllers")
        FileUtils.makedirs("#{name}/models")
        FileUtils.makedirs("#{name}/test")
        FileUtils.makedirs("#{name}/views")

        template = get_template_for( :service )
        resultant_string = template.result( get_binding_for_service( name ) )
        File.open("#{name}/loader.rb", 'w') {|f| f.puts resultant_string }

        template = get_template_for( :rackup )
        resultant_string = template.result( get_binding_for_service( name ) )
        File.open("#{name}/config.ru", 'w') {|f| f.puts resultant_string }

        template = get_template_for( :constants )
        resultant_string = template.result( get_binding_for_service( name ) )
        File.open("#{name}/config/constants.yaml", 'w') {|f| f.puts resultant_string }

        template = get_template_for( :hooks )
        resultant_string = template.result( get_binding_for_service( name ) )
        File.open("#{name}/hooks.rb", 'w') {|f| f.puts resultant_string }

        # Added following lines to generate 'Gemfile' automatically.
        template = get_template_for( :gemfile )
        resultant_string = template.result( get_binding_for_service( name ) )
        File.open("#{name}/Gemfile", 'w') {|f| f.puts resultant_string }
      end
      # Generate a new RESTRack service.  This does not use EventMachine and can
      # be used with any Rack supported web server.
      def generate_synchronous_service(name)
        @async = false
        generate_service(name)
        @async = nil
      end
      # Generate a new RESTRack service that uses EventMachine. This can only be
      # used with web servers that use or support EventMachine (Thin, Rainbows).
      def generate_asynchronous_service(name)
        @async = true
        generate_service(name)
        @async = nil
      end

      private

      def get_template_for(type)
        template_file = File.new(File.join(File.dirname(__FILE__),"generator/#{TEMPLATE[type]}"))
        template = ERB.new( template_file.read, nil, "%" )
      end

      def get_binding_for_controller(name)
        @name = name
        @service_name = get_service_name
        binding
      end

      def get_binding_for_descendant_controller(name, parent)
        @name = name
        @parent = parent
        @service_name = get_service_name
        binding
      end

      def get_binding_for_service(name)
        @service_name = name
        binding
      end

      def get_service_name
        line = ''
        begin
          File.open(File.join(base_dir, 'config/constants.yaml')) { |f| line = f.gets }
        rescue
          raise File.join(base_dir, 'config/constants.yaml') + ' not found or could not be opened!'
        end
        begin
          check = line.match(/#GENERATOR-CONST#.*Application-Namespace\s*=>\s*(.+)/)[0]
          service_name = $1
        rescue
          raise '#GENERATOR-CONST# line has been removed or modified in config/constants.yaml.'
        end
        return service_name
      end

      def base_dir
        base_dir = nil
        this_path = File.join( Dir.pwd, 'config/constants.yaml')
        while this_path != '/config/constants.yaml'
          if File.exists?( this_path )
            base_dir = Dir.pwd
            break
          else
            this_path = File.join('..', this_path)
          end
        end
        raise 'The config/constants.yaml file could not found when determining base_dir!' unless base_dir
        return base_dir
      end

    end # class << self

  end # class
end # module
