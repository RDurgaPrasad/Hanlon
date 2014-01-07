#

require 'json'
require 'api_utils'

module Razor
  module WebService
    module Broker

      class APIv1 < Grape::API

        version :v1, :using => :path, :vendor => "razor"
        format :json
        default_format :json

        # Root namespace for broker objects
        # used to find them in object space for plugin checking
        BROKER_PREFIX = "ProjectRazor::BrokerPlugin::"

        rescue_from ProjectRazor::Error::Slice::InvalidUUID do |e|
          Rack::Response.new(
              Razor::WebService::Response.new(400, e.class.name, e.message).to_json,
              400,
              { "Content-type" => "application/json" }
          )
        end

        rescue_from Grape::Exceptions::Validation do |e|
          Rack::Response.new(
              Razor::WebService::Response.new(400, e.class.name, e.message).to_json,
              400,
              { "Content-type" => "application/json" }
          )
        end

        rescue_from :all do |e|
          raise e
          Rack::Response.new(
              Razor::WebService::Response.new(500, e.class.name, e.message).to_json,
              500,
              { "Content-type" => "application/json" }
          )
        end

        helpers do

          def content_type_header
            settings[:content_types][env['api.format']]
          end

          def api_format
            env['api.format']
          end

          def is_uuid?(string_)
            string_ =~ /[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}/
          end

          def get_data_ref
            Razor::WebService::Utils::get_data
          end

          def slice_success_web(slice, command, response, options = {})
            Razor::WebService::Utils::rz_slice_success_web(slice, command, response, options)
          end

          def response_with_status_web(slice, command, response, options = {})
            Razor::WebService::Utils::rz_response_with_status(slice, command, response, options)
          end

        end

        resource :broker do

          # GET /broker
          # Query for defined brokers.
          get do
            slice_ref = ProjectRazor::Slice.new
            Razor::WebService::Response.new(200, 'OK', 'Success.', slice_ref.get_object("broker_instances", :broker))
          end     # end GET /broker

          # POST /broker
          # Create a Razor broker
          #   parameters:
          #     plugin            | String | The "plugin" to use for the new broker   |         | Default: unavailable
          #     name              | String | The "name" to use for the new broker     |         | Default: unavailable
          #     description       | String | The description of the new broker        |         | Default: unavailable
          #     req_metadata_hash | Hash   | The metadata to use for the new broker   |         | Default: unavailable
          params do
            requires "plugin", type: String
            requires "name", type: String
            requires "description", type: String
            requires "req_metadata_hash", type: Hash
          end
          post do
            plugin = params["plugin"]
            name = params["name"]
            description = params["description"]
            req_metadata_hash = params["req_metadata_hash"]
            # use the arguments passed in to create a new broker
            broker_slice = ProjectRazor::Slice::Broker.new([])
            broker = broker_slice.new_object_from_template_name(BROKER_PREFIX, plugin)
            raise ProjectRazor::Error::Slice::MissingArgument, "Must Provide Required Metadata [req_metadata_hash]" unless
                req_metadata_hash
            broker.web_create_metadata(req_metadata_hash)
            broker.name             = name
            broker.user_description = description
            broker.is_template      = false
            # persist that broker, and print the result (or raise an error if cannot persist it)
            get_data_ref.persist_object(broker)
            raise(ProjectRazor::Error::Slice::CouldNotCreate, "Could not create Broker Target") unless broker
            response_with_status_web(broker_slice, :create_broker, [broker], :success_type => :created)
          end     # end POST /broker

          resource :plugins do

            # GET /broker/plugins
            # Query for available broker plugins
            get do
              slice_ref = ProjectRazor::Slice.new
              broker_plugins = slice_ref.get_child_templates(ProjectRazor::BrokerPlugin)
              # convert each element of the array to a hash, then use that array of hashes
              # to construct the response
              Razor::WebService::Response.new(200, 'OK', 'Success.', broker_plugins.collect { |object| object.to_hash })
            end     # end GET /broker/plugins

          end     # end resource /broker/plugins

          resource '/:uuid' do

            # GET /broker/{uuid}
            # Query for the state of a specific broker.
            params do
              requires :uuid, type: String
            end
            get do
              slice_ref = ProjectRazor::Slice.new
              broker_uuid = params[:uuid]
              broker = slice_ref.get_object("broker instances", :broker, broker_uuid)
              raise ProjectRazor::Error::Slice::NotFound, "Broker Target UUID: [#{broker_uuid}]" unless broker && (broker.class != Array || broker.length > 0)
              Razor::WebService::Response.new(200, 'OK', 'Success.', broker)
            end     # end GET /broker/{uuid}

            # PUT /broker/{uuid}
            # Update a Razor broker (any of the the name, description, or req_metadata_hash
            # can be updated using this endpoint; note that the broker plugin cannot be updated
            # once a broker is created
            #   parameters:
            #     name              | String | The "name" to use for the new broker     |         | Default: unavailable
            #     description       | String | The description of the new broker        |         | Default: unavailable
            #     req_metadata_hash | Hash   | The metadata to use for the new broker   |         | Default: unavailable
            params do
              requires :uuid, type: String
              optional "name", type: String
              optional "description", type: String
              optional "req_metadata_hash", type: Hash
            end
            put do
              # get the input parameters that were passed in as part of the request
              # (at least one of these should be a non-nil value)
              broker_uuid = params[:uuid]
              plugin = params[:plugin]
              name = params[:name]
              description = params[:description]
              req_metadata_hash = params[:req_metadata_hash]
              # check the values that were passed in (and gather new meta-data if
              # the --change-metadata flag was included in the update command and the
              # command was invoked via the CLI...it's an error to use this flag via
              # the RESTful API, the req_metadata_hash should be used instead)
              broker_slice = ProjectRazor::Slice::Broker.new([])
              broker = broker_slice.get_object("broker_with_uuid", :broker, broker_uuid)
              raise ProjectRazor::Error::Slice::InvalidUUID, "Invalid Broker UUID [#{broker_uuid}]" unless broker && (broker.class != Array || broker.length > 0)
              # fill in the fields with the new values that were passed in (if any)
              broker.name             = name if name
              broker.user_description = description if description
              broker.is_template      = false
              broker.web_create_metadata(req_metadata_hash) if req_metadata_hash
              raise ProjectRazor::Error::Slice::CouldNotUpdate, "Could not update Broker Target [#{broker.uuid}]" unless broker.update_self
              response_with_status_web(broker_slice, :update_broker, [broker], :success_type => :updated)
            end     # end PUT /broker/{uuid}

            # DELETE /broker/{uuid}
            # Remove a Razor broker (by UUID)
            params do
              requires :uuid, type: String
            end
            delete do
              broker_slice = ProjectRazor::Slice::Broker.new([])
              broker_uuid = params[:uuid]
              broker = broker_slice.get_object("broker_with_uuid", :broker, broker_uuid)
              raise ProjectRazor::Error::Slice::InvalidUUID, "Cannot Find Broker with UUID: [#{broker_uuid}]" unless broker && (broker.class != Array || broker.length > 0)
              raise ProjectRazor::Error::Slice::CouldNotRemove, "Could not remove Broker [#{broker.uuid}]" unless get_data_ref.delete_object(broker)
              slice_success_web(broker_slice, :remove_broker_by_uuid, "Broker [#{broker.uuid}] removed", :success_type => :removed)
            end     # end DELETE /broker/{uuid}

          end     # end resource /broker/:uuid

        end     # end resource /broker

      end

    end

  end

end
