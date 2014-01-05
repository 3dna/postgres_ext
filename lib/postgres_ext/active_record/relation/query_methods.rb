module PostgresExt::ActiveRecord
  module QueryMethods
    module WhereChain
      def overlap(opts)
        opts.each do |key, value|
          @scope = @scope.where(arel_table[key].overlap(value))
        end
        @scope
      end

      def contained_within(opts)
        opts.each do |key, value|
          @scope = @scope.where(arel_table[key].contained_within(value))
        end

        @scope
      end

      def contained_within_or_equals(opts)
        opts.each do |key, value|
          @scope = @scope.where(arel_table[key].contained_within_or_equals(value))
        end

        @scope
      end

      def contains(opts)
        opts.each do |key, value|
          @scope = @scope.where(arel_table[key].contains(value))
        end

        @scope
      end

      def contains_or_equals(opts)
        opts.each do |key, value|
          @scope = @scope.where(arel_table[key].contains_or_equals(value))
        end

        @scope
      end

      def any(opts)
        equality_to_function('ANY', opts)
      end

      def all(opts)
        equality_to_function('ALL', opts)
      end

      private

      def arel_table
        @arel_table ||= @scope.engine.arel_table
      end

      def equality_to_function(function_name, opts)
        opts.each do |key, value|
          any_function = Arel::Nodes::NamedFunction.new(function_name, [arel_table[key]])
          predicate = Arel::Nodes::Equality.new(value, any_function)
          @scope = @scope.where(predicate)
        end

        @scope
      end
    end

    def self.prepended(klass)
      [:with].each do |name|
        klass.class_eval <<-CODE, __FILE__, __LINE__ + 1
       def #{name}_values                   # def select_values
         @values[:#{name}] || []            #   @values[:select] || []
       end                                  # end
                                            #
       def #{name}_values=(values)          # def select_values=(values)
         raise ImmutableRelation if @loaded #   raise ImmutableRelation if @loaded
         @values[:#{name}] = values         #   @values[:select] = values
       end                                  # end
        CODE
      end

      [:rank].each do |name|
        klass.class_eval <<-CODE, __FILE__, __LINE__ + 1
        def #{name}_value=(value)            # def readonly_value=(value)
          raise ImmutableRelation if @loaded #   raise ImmutableRelation if @loaded
          @values[:#{name}] = value          #   @values[:readonly] = value
        end                                  # end

        def #{name}_value                    # def readonly_value
          @values[:#{name}]                  #   @values[:readonly]
        end                                  # end
        CODE
      end
    end
    def with(*args)
      check_if_method_has_arguments!('with', args)
      spawn.with!(*args.compact.flatten)
    end

    def with!(*args)
      self.with_values += args
      self
    end

    def ranked(options = :order)
      spawn.ranked! options
    end

    def ranked!(value)
      self.rank_value = value
      self
    end

    def build_arel
      arel = super

      build_with(arel, with_values)

      build_rank(arel, rank_value) if rank_value

      arel
    end

    def build_with(arel, withs)
      with_statements = withs.flat_map do |with_value|
        case with_value
        when String
          with_value
        when Hash
          with_value.map  do |name, expression|
            case expression
            when String
              select = Arel::SqlLiteral.new "(#{expression})"
            when ActiveRecord::Relation
              select = Arel::SqlLiteral.new "(#{expression.to_sql})"
            end
            as = Arel::Nodes::As.new Arel::SqlLiteral.new(name.to_s), select
          end
        end
      end
      arel.with with_statements unless with_statements.empty?
    end

    def build_rank(arel, rank_window_options)
      unless arel.projections.count == 1 && Arel::Nodes::Count === arel.projections.first
        rank_window = case rank_window_options
          when :order
            arel.orders
          when Symbol
            table[rank_window_options].asc
          when Hash
            rank_window_options.map { |field, dir| table[field].send(dir) }
          else
            Arel::Nodes::SqlLiteral.new "(#{rank_window_options})"
          end

        unless rank_window.blank?
          rank_node = Arel::Nodes::SqlLiteral.new 'rank()'
          window = Arel::Nodes::Window.new
          if String === rank_window
            window = window.frame rank_window
          else
            window = window.order(rank_window)
          end
          over_node = Arel::Nodes::Over.new rank_node, window

          arel.project(over_node)
        end
      end
    end
  end
end
