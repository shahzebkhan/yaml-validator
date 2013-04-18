require 'yaml'
require 'yaml-validator/version'
require_relative './helpers'
require_relative './pluralization-validator'

class YamlValidator
  
  def initialize(root_path, base_file, new_file, options = {})
    @options = options
    @options[:show_missing] ||= true
    @root_path = root_path
    @base_file = base_file
    @new_file = new_file
  end
  
  def en
    return @en unless @en.nil?

    fullpath = File.join(@root_path, @base_file)
    return nil unless File.exists?(fullpath)
    @en = YAML.load_file(fullpath)['en'][@base_file.split('.')[0]]
    @en = Helpers.normalize_yaml(@en)
  end
  
  def en_with_vars
    return nil if en.nil?
    @en_with_vars ||= get_all_variables(en)
  end
  
  def validate()
    if en_with_vars.nil?
      return ["no en.yml file in the directory (an en.yml file is required as reference)"]
    end
    yml_files = File.join(@root_path, @new_file.length > 0 ? @new_file : '*.yml' )
    errors = []
    filter = /\/([a-z]*)\.(en|es)\.(yml)\z/
    Dir[yml_files].grep(filter).each do |filename|
      next if File.basename(filename) == @base_file
      errors.concat validate_yaml(filename)
    end
    errors
  end
  
  def validate_yaml(filepath)
    filename = File.basename(filepath)
    
    begin
      yaml_object = YAML.load_file(filepath)
    rescue Psych::SyntaxError => e
      return [e.message.sub(/^\([^)]+\)/, filename)]
    end
    
    errors = validate_root_language(yaml_object, File.basename(filename))

    # Move to the third root in the yml file
    [1, 2].each do 
      yaml_object = yaml_object[yaml_object.keys[0]]
    end
    yaml_object = Helpers.normalize_yaml(yaml_object)
    errors += validate_yaml_object('', yaml_object)
    if @options[:show_missing]
      errors.concat find_missing_translations(yaml_object)
      errors.concat find_missing_pluralizations(filename, yaml_object)
    end
    
    errors.map { |err| "#{filename}: #{err}" }
  end
  
  def validate_root_language(yaml_object, file_name)
    errors = []

    lang = yaml_object.keys.first
    if lang != file_name.split(".").first
      errors << "different root language (#{lang})"
    end

    errors
  end

  def validate_yaml_object(full_key, yaml_object)
    return [] if yaml_object.nil?
    errors = []
    is_pluralization = Helpers.pluralization? yaml_object
    
    yaml_object.each do |key, value|
      full_subkey = (full_key.empty?) ? key : "#{full_key}.#{key}"
      if value.is_a? String
        errors.concat validate_item(full_subkey, value, is_pluralization)
      else
        errors.concat validate_yaml_object(full_subkey, value)
      end
    end
    errors
  end
  
  def find_missing_translations(yaml_object)
    find_missing_translations_in_en_object('', en, yaml_object)
  end
  
  def find_missing_translations_in_en_object(full_key, en_yaml_object, yaml_object)
    return [] if en_yaml_object.nil?
    errors = []
    
    en_yaml_object.each do |key, value|
      full_subkey = (full_key.empty?) ? key : "#{full_key}.#{key}"
      if value.is_a? String or value.is_a? Symbol
        if self.class.find_key_in_yaml_object(full_subkey, yaml_object).nil?
          errors << "missing translation for #{full_subkey} ('#{value}')"
        end
      else
        errors.concat find_missing_translations_in_en_object(full_subkey, value, yaml_object)
      end
    end
    errors
  end

  def find_missing_pluralizations(filename, yaml_object)
    language = File.basename(filename, '.*')
    PluralizationValidator.validate(language, yaml_object)
  end
  
  def self.find_key_in_yaml_object(full_key, yaml_object)
    position = yaml_object
    full_key.split('.').each do |key|
      return nil unless position.is_a? Hash
      position = position[key]
    end
    
    if position.is_a? String or position.is_a? Symbol
      position
    else
      nil
    end
  end
  
  def validate_item(full_key, value, is_pluralization = false)
    real_vars = get_key_en_vars(full_key)
    if real_vars.nil?
      if is_pluralization
        return []
      else
        # return ["#{full_key} doesn't exist in #{@base_file}"]
        return []
      end
    end

    used_vars = identify_variables(value)

    errors = []
    used_vars.each do |var|
      unless real_vars.include? var
        errors << "#{full_key}: missing variable '#{var}' (available options: #{real_vars.join(', ')})"
      end
    end
    errors
  end
  
  def get_key_en_vars(full_key)
    position = en_with_vars
    full_key.split('.').each do |key|
      return nil if position.is_a? Array
      return nil if position.nil?
      position = position[key]
    end
    if position.is_a? Array
      position
    else
      nil
    end
  end
  
  def get_all_variables(yaml_object)
    return {} if yaml_object.nil?
    with_vars = {}
    
    yaml_object.each do |key, value|
      if value.is_a? String
        with_vars[key] = identify_variables(value)
      elsif value.is_a? Symbol
        with_vars[key] = {}
      else
        with_vars[key] = get_all_variables(value)
      end
    end
    with_vars
  end
  
  def identify_variables(string)
    string.scan(/%\{([^}]+)\}/).map(&:first)
  end
  
end

