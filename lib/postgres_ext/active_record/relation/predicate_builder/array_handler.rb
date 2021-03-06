require 'active_record/relation/predicate_builder'
require 'active_record/relation/predicate_builder/array_handler'

require 'active_support/concern'

module ActiveRecord
  class PredicateBuilder
    module ArrayHandlerPatch
      extend ActiveSupport::Concern

      included do
        def call_with_feature(attribute, value)
          engine = attribute.relation.engine
          column = engine.connection.schema_cache.columns(attribute.relation.name).detect{ |col| col.name.to_s == attribute.name.to_s }
          if column.array
            attribute.eq(value)
          else
            call_without_feature(attribute, value)
          end
        end

        alias_method_chain(:call, :feature)
      end

      module ClassMethods

      end
    end
  end
end

ActiveRecord::PredicateBuilder::ArrayHandler.send(:include, ActiveRecord::PredicateBuilder::ArrayHandlerPatch)
