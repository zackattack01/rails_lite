require 'active_support/inflector'
require_relative 'db_connection'
require_relative 'searchable'
require_relative 'associatable'

class SQLObject
  extend Searchable
  extend Associatable

  def self.set_columns
    cols = DBConnection.execute2(<<-SQL) 
      SELECT 
        * 
      FROM 
       #{table_name} 
      LIMIT 
        1 
    SQL

    cols.first.map(&:to_sym)
  end

  def self.columns
    @cols ||= set_columns
  end

  def self.finalize!
    columns.each do |ivar|
      define_method(ivar) do 
        attributes[ivar]
      end

      define_method("#{ivar}=") do |value|
        attributes[ivar] = value
      end
    end
  end

  def self.table_name=(table_name)
    @table_name = table_name
  end

  def self.table_name
    @table_name ||= self.to_s.tableize
  end

  def self.all
    parse_all(DBConnection.execute(<<-SQL) 
                SELECT 
                  * 
                FROM 
                  #{table_name} 
              SQL
              )
  end

  def self.parse_all(results)
    results.map { |attr_hash| new(attr_hash) }
  end

  def self.find(id)
    found = DBConnection.execute(<<-SQL, id) 
              SELECT 
                * 
              FROM 
                #{table_name}
              WHERE
                id = ?
              LIMIT
                1
            SQL
    
    found.empty? ? nil : new(found.first)
  end

  def initialize(params = {})
    params.each do |attr_name, value|
      unless self.class.columns.include?(attr_name.to_sym)
        raise "unknown attribute '#{attr_name}'"
      end
      send("#{attr_name}=", value)
    end
  end

  def attributes
    @attributes ||= {}
  end

  def attribute_values
    self.class.columns.map { |attr| send(attr) }
  end

  def insert
    col_names = "(#{self.class.columns[1..-1].join(', ')})"
    question_marks = "(#{(['?'] * (col_names.count(',') + 1)).join(', ')})"
    
    DBConnection.execute(<<-SQL, *attribute_values.drop(1)) 
      INSERT INTO
        #{self.class.table_name} #{col_names}
      VALUES
        #{question_marks}
    SQL

    self.id = DBConnection.last_insert_row_id
  end

  def update
    updates = self.class.columns[1..-1].product(['?']).map do |attr_name, val|
      "#{attr_name} = #{val}"
    end.join(', ')

    DBConnection.execute(<<-SQL, *attribute_values.rotate)
      UPDATE
        #{self.class.table_name} 
      SET
        #{updates}
      WHERE
        id = ?
    SQL
  end

  def save
    id.nil? ? insert : update
  end
end