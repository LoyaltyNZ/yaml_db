module SerializationHelper

  class Base
    attr_reader :extension

    def initialize(helper)
      @dumper = helper.dumper
      @loader = helper.loader
      @extension = helper.extension
    end

    def dump(filename)
      disable_logger
      @dumper.dump(File.new(filename, "w"))
      reenable_logger
    end

    def dump_to_dir(dirname)
      Dir.mkdir(dirname)
      tables = @dumper.tables
      tables.each do |table|
        file = File.new "#{dirname}/#{table}.#{@extension}", "w"
        @dumper.dump_table file, table
      end
    end

    def load(filename, truncate = true)
      disable_logger
      @loader.load(File.new(filename, "r"), truncate)
      reenable_logger
    end

    def load_from_dir(dirname, truncate = true)
      Dir.entries(dirname).each do |filename|
        if filename =~ /^[.]/
          next
        end
        @loader.load(File.new("#{dirname}/#{filename}", "r"), truncate)
      end   
    end

    def disable_logger
      @@old_logger = ActiveRecord::Base.logger
      ActiveRecord::Base.logger = nil
    end

    def reenable_logger
      ActiveRecord::Base.logger = @@old_logger
    end
  end
  
  class Load

  end

  module Utils

    def self.unhash(hash, keys)
      keys.map { |key| hash[key] }
    end

    def self.unhash_records(records, keys)
      records.each_with_index do |record, index|
        records[index] = unhash(record, keys)
      end

      records
    end

    def self.convert_booleans(records, columns)
      records.each do |record|
        columns.each do |column|
          next if is_boolean(record[column])
          record[column] = (record[column] == 't' or record[column] == '1')
        end
      end
      records
    end

    def self.boolean_columns(table)
      columns = ActiveRecord::Base.connection.columns(table).reject { |c| c.type != :boolean }
      columns.map { |c| c.name }
    end

    def self.is_boolean(value)
      value.kind_of?(TrueClass) or value.kind_of?(FalseClass)
    end

    def self.quote_table(table)
      ActiveRecord::Base.connection.quote_table_name(table)
    end

  end

  class Dump
    def self.before_table(io, table)

    end

    def self.dump(io)
      tables.each do |table|
        before_table(io, table)
        dump_table(io, table)
        after_table(io, table)
      end
    end

    def self.after_table(io, table)

    end

    def self.tables
      ActiveRecord::Base.connection.tables.reject { |table| ['schema_info', 'schema_migrations'].include?(table) }
    end

    def self.dump_table(io, table)
      return if table_record_count(table).zero?

      dump_table_columns(io, table)
      dump_table_records(io, table)
    end

    def self.table_column_names(table)
      ActiveRecord::Base.connection.columns(table).map { |c| c.name }
    end


    def self.each_table_page(table, records_per_page=1000)
      total_count = table_record_count(table)
      pages = (total_count.to_f / records_per_page).ceil - 1
      id = table_column_names(table).first
      boolean_columns = SerializationHelper::Utils.boolean_columns(table)
      quoted_table_name = SerializationHelper::Utils.quote_table(table)

      (0..pages).to_a.each do |page|
        sql = ActiveRecord::Base.connection.add_limit_offset!("SELECT * FROM #{quoted_table_name} ORDER BY #{id}",
                                                              :limit => records_per_page, :offset => records_per_page * page
        )
        records = ActiveRecord::Base.connection.select_all(sql)
        records = SerializationHelper::Utils.convert_booleans(records, boolean_columns)
        yield records
      end
    end

    def self.table_record_count(table)
      ActiveRecord::Base.connection.select_one("SELECT COUNT(*) FROM #{SerializationHelper::Utils.quote_table(table)}").values.first.to_i
    end

  end

end