module RESTRack
  
  # All RESTRack controllers should descend from ResourceController.  This class
  # provides the methods for your controllers.
  #
  #                    HTTP Verb: |    GET    |   PUT     |   POST    |   DELETE
  # Collection URI (/widgets/):   |   index   |   replace |   create  |   drop
  # Element URI   (/widgets/42):  |   show    |   update  |   add     |   destroy
  #
  
  class ResourceController
    # TODO: Check input and output
    attr_reader :input, :output, :action, :id

    # Base initialization method for resources and storage of request input
    # This method should not be overriden in decendent classes.
    def self.__init(resource_request)
      __self = self.new
      return __self.__init(resource_request)
    end
    def __init(resource_request)
      @resource_request = resource_request
      self
    end

    # Call the controller's action and return output in the proper format.
    def call
      self.determine_action
      args = []
      args << @id unless @id.blank?
      self.send(@action.to_sym, *args)
    end

    def method_missing(method_sym, *arguments, &block)
      raise HTTP405MethodNotAllowed, 'Method not provided on controller.'
    end
  
    # Methods to be overridden in descendant controllers, defined here for determine_action lookup.
    def index;       end
    def replace;     end
    def create;      end
    def drop;        end
    def show(id);    end
    def update(id);  end
    def add(id);     end
    def destroy(id); end

    protected
    # all internal methods are protected rather than private so that calling methods *could* be overriden if necessary.
    
    # This method allows one to access a related resource, without providing a direct link to specific relation(s).
    def self.pass_through_to(entity, opts = {})
      entity_name = opts[:as] || entity
      define_method( entity_name.to_sym,
        Proc.new do |calling_id| # The calling resource's id will come along for the ride when the new bridging method is called magically from ResourceController#call
          @resource_request.call_controller(entity)
        end
      )
    end

    # This method defines that there is a single link to a member from an entity collection.
    # The second parameter is an options hash to support setting the local name of the relation via ':as => :foo'.
    # The third parameter to the method is a Proc which accepts the calling entity's id and returns the id of the relation to which we're establishing the link.
    # This adds an accessor instance method whose name is the entity's class.
    def self.has_relationship_to(entity, opts = {}, &get_entity_id_from_relation_id)
      entity_name = opts[:as] || entity
      define_method( entity_name.to_sym,
        Proc.new do |calling_id| # The calling resource's id will come along for the ride when the new bridging method is called magically from ResourceController#call
          id = get_entity_id_from_relation_id.call(@id)
          @resource_request.url_chain.unshift(id)
          @resource_request.call_controller(entity)
        end
      )
    end

    # This method defines that there are multiple links to members from an entity collection (an array of entity identifiers).
    # This adds an accessor instance method whose name is the entity's class.
    def self.has_relationships_to(entity, opts = {}, &get_entity_id_from_relation_id)
      entity_name = opts[:as] || entity
      define_method( entity_name.to_sym,
        Proc.new do |old_id| # The parent resource's id will come along for the ride when the new bridging method is called magically from ResourceController#call
          entity_array = get_entity_id_from_relation_id.call(@id)
          index = @resource_request.url_chain.shift # TODO: Trap error on no index supplied
          unless index < entity_array.length
            raise HTTP404ResourceNotFound, 'You requested an item by index and the index was larger than this item\'s list of relations\' length.'
          end
          id = entity_array[index]
          @resource_request.url_chain.unshift(id)
          @resource_request.call_controller(entity)
        end
      )
    end
    
    # This method defines that there are multiple links to members from an entity collection (an array of entity identifiers).
    # This adds an accessor instance method whose name is the entity's class.
    def self.has_defined_relationships_to(entity, opts = {}, &get_entity_id_from_relation_id)
      entity_name = opts[:as] || entity
      define_method( entity_name.to_sym,
        Proc.new do |old_id| # The parent resource's id will come along for the ride when the new bridging method is called magically from ResourceController#call
          entity_array = get_entity_id_from_relation_id.call(@id)
          id = @resource_request.url_chain.shift # TODO: Trap error on no id supplied in url
          unless entity_array.include?( id )
            raise HTTP404ResourceNotFound, 'Relation entity does not belong to referring resource.'
          end
          @resource_request.url_chain.unshift(id)
          @resource_request.call_controller(entity)
        end
      )
    end

    # This method defines that there are mapped links to members from an entity collection (a hash of entity identifiers).
    # This adds an accessor instance method whose name is the entity's class.
    def self.has_mapped_relationships_to(entity, opts = {}, &get_entity_id_from_relation_id)
      entity_name = opts[:as] || entity
      define_method( entity_name.to_sym,
        Proc.new do |old_id| # The parent resource's id will come along for the ride when the new bridging method is called magically from ResourceController#call
          entity_map = get_entity_id_from_relation_id.call(@id)
          key = @resource_request.url_chain.shift
          id = entity_map[key.to_sym]
          @resource_request.url_chain.unshift(id)
          @resource_request.call_controller(entity)
        end
      )
    end

    # Allows decendent controllers to set a data type for the id other than the default.
    def self.keyed_with_type(klass)
      @key_type = klass
    end

    # Find the action, and id if relevant, that the controller must call.
    def determine_action
      term = @resource_request.url_chain.shift
      if term.nil?
        @id = nil
        @action = nil
      elsif self.methods.include?( term.to_sym )
        @id = nil
        @action = term.to_sym
      else
        @id = term
        term = @resource_request.url_chain.shift
        if term.nil?
          @action = nil
        elsif self.methods.include?( term.to_sym )
          @action = term.to_sym
        else
          raise HTTP405MethodNotAllowed, 'Action not provided or found and unknown HTTP request method.'
        end
      end
      format_id
      # If the action is not set with the request URI, determine the action from HTTP Verb.
      get_action_from_context if @action.blank?
    end

    # This method is used to convert the id coming off of the path stack, which is in string form, into another data type if one has been set.
    def format_id
      return nil unless @id
      @key_type ||= nil
      unless @key_type.blank?
        if @key_type == Fixnum
          @id = @id.to_i
        elsif @key_type == Float
          @id = @id.to_f
        else
          raise HTTP500ServerError, "Invalid key identifier type specified on resource #{self.class.to_s}."
        end
      else
        @key_type = String
      end
    end
    
    # Get action from HTTP verb
    def get_action_from_context
      if @resource_request.request.get?
        @action = @id.blank? ? :index   : :show
      elsif @resource_request.request.put?
        @action = @id.blank? ? :replace : :update
      elsif @resource_request.request.post?
        @action = @id.blank? ? :create  : :add
      elsif @resource_request.request.delete?
        @action = @id.blank? ? :drop    : :destroy
      else
        raise HTTP405MethodNotAllowed, 'Action not provided or found and unknown HTTP request method.'
      end
    end

  end # class ResourceController
end # module RESTRack
