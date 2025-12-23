class SegmentQueryBuilder
  def initialize(segment)
    @segment = segment
    @list = segment.list
  end

  def build
    query = @list.active_subscribers

    return query if @segment.criteria.blank?

    @segment.criteria.each do |criterion|
      query = apply_criterion(query, criterion)
    end

    query
  end

  private

  def apply_criterion(query, criterion)
    field = criterion["field"]
    operator = criterion["operator"]
    value = criterion["value"]

    case field
    when "email"
      apply_email_filter(query, operator, value)
    when "status"
      query.where(status: value)
    when "created_at", "updated_at"
      apply_date_filter(query, field, operator, value)
    when /^custom_attributes\./
      # Custom attribute filtering
      attr_key = field.sub("custom_attributes.", "")
      apply_json_filter(query, attr_key, operator, value)
    else
      query
    end
  end

  def apply_email_filter(query, operator, value)
    case operator
    when "equals"
      query.where(email: value)
    when "not_equals"
      query.where.not(email: value)
    when "contains"
      query.where("email LIKE ?", "%#{sanitize_like(value)}%")
    when "starts_with"
      query.where("email LIKE ?", "#{sanitize_like(value)}%")
    when "ends_with"
      query.where("email LIKE ?", "%#{sanitize_like(value)}")
    else
      query
    end
  end

  def apply_date_filter(query, field, operator, value)
    begin
      date = Date.parse(value.to_s)
    rescue ArgumentError
      return query
    end

    case operator
    when "before"
      query.where("#{field} < ?", date)
    when "after"
      query.where("#{field} > ?", date)
    when "equals"
      query.where("DATE(#{field}) = ?", date)
    when "between"
      # value should be array [start_date, end_date]
      if value.is_a?(Array) && value.length == 2
        query.where("#{field} BETWEEN ? AND ?", value[0], value[1])
      else
        query
      end
    else
      query
    end
  end

  def apply_json_filter(query, key, operator, value)
    # SQLite JSON functions - escape the key for safety
    escaped_key = ActiveRecord::Base.connection.quote(key)
    json_path = "$.#{key}"

    case operator
    when "equals"
      # For strings, wrap in quotes for JSON comparison
      json_value = value.is_a?(String) ? value.to_json : value
      query.where("json_extract(subscribers.custom_attributes, ?) = ?", json_path, json_value)
    when "not_equals"
      json_value = value.is_a?(String) ? value.to_json : value
      query.where("json_extract(subscribers.custom_attributes, ?) != ?", json_path, json_value)
    when "contains"
      # For string contains, use LIKE on extracted JSON value
      query.where("json_extract(subscribers.custom_attributes, ?) LIKE ?",
                  json_path, "%#{sanitize_like(value.to_s)}%")
    when "exists"
      query.where("json_extract(subscribers.custom_attributes, ?) IS NOT NULL", json_path)
    when "not_exists"
      query.where("json_extract(subscribers.custom_attributes, ?) IS NULL", json_path)
    when "greater_than"
      query.where("CAST(json_extract(subscribers.custom_attributes, ?) AS REAL) > ?",
                  json_path, value.to_f)
    when "less_than"
      query.where("CAST(json_extract(subscribers.custom_attributes, ?) AS REAL) < ?",
                  json_path, value.to_f)
    when "greater_than_or_equal"
      query.where("CAST(json_extract(subscribers.custom_attributes, ?) AS REAL) >= ?",
                  json_path, value.to_f)
    when "less_than_or_equal"
      query.where("CAST(json_extract(subscribers.custom_attributes, ?) AS REAL) <= ?",
                  json_path, value.to_f)
    else
      query
    end
  end

  def sanitize_like(value)
    # Escape special LIKE characters
    value.gsub(/[%_\\]/) { |match| "\\#{match}" }
  end
end
