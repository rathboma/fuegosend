class CustomFieldDefinition < ApplicationRecord
  belongs_to :account

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :field_type, inclusion: { in: %w[text number date boolean email url] }

  # Validate a value according to this field's rules
  def validate_value(value)
    return [false, "is required"] if required && value.blank?

    case field_type
    when "number"
      return [false, "must be a number"] unless value.to_s.match?(/\A-?\d+(\.\d+)?\z/)
    when "email"
      return [false, "must be a valid email"] unless value.to_s.match?(URI::MailTo::EMAIL_REGEXP)
    when "url"
      begin
        uri = URI.parse(value.to_s)
        return [false, "must be a valid URL"] unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        return [false, "must be a valid URL"]
      end
    when "boolean"
      return [false, "must be true or false"] unless [true, false, "true", "false", "1", "0"].include?(value)
    end

    # Apply custom validation rules
    if validation_rules.present?
      apply_validation_rules(value)
    else
      [true, nil]
    end
  end

  private

  def apply_validation_rules(value)
    # Implement custom validation rules like min_length, max_length, pattern, etc.
    rules = validation_rules

    if rules["min_length"] && value.to_s.length < rules["min_length"]
      return [false, "must be at least #{rules['min_length']} characters"]
    end

    if rules["max_length"] && value.to_s.length > rules["max_length"]
      return [false, "must be at most #{rules['max_length']} characters"]
    end

    if rules["pattern"] && !value.to_s.match?(Regexp.new(rules["pattern"]))
      return [false, rules["pattern_message"] || "does not match required pattern"]
    end

    [true, nil]
  end
end
