class SubscribersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_subscriber, only: [:show, :edit, :update, :destroy]

  # GET /subscribers
  def index
    @subscribers = current_account.subscribers.order(created_at: :desc)

    # Filter by status
    if params[:status].present?
      @subscribers = @subscribers.where(status: params[:status])
    end

    # Filter by list
    if params[:list_id].present?
      @list = current_account.lists.find(params[:list_id])
      @subscribers = @subscribers.joins(:list_subscriptions)
                                 .where(list_subscriptions: { list_id: @list.id, status: "active" })
    end

    # Search by email
    if params[:search].present?
      @subscribers = @subscribers.where("email LIKE ?", "%#{params[:search]}%")
    end

    # Paginate (25 per page)
    @subscribers = @subscribers.limit(25).offset((params[:page].to_i - 1) * 25)
    @total_count = current_account.subscribers.count
  end

  # GET /subscribers/:id
  def show
    @list_subscriptions = @subscriber.list_subscriptions.includes(:list)
    @recent_campaigns = @subscriber.campaign_sends.includes(:campaign).order(created_at: :desc).limit(10)
  end

  # GET /subscribers/new
  def new
    @subscriber = current_account.subscribers.new
    @lists = current_account.lists
  end

  # POST /subscribers
  def create
    @subscriber = current_account.subscribers.find_or_initialize_by(email: subscriber_params[:email])
    @lists = current_account.lists

    # Set attributes
    @subscriber.assign_attributes(subscriber_params.except(:email, :list_ids, :custom_attributes))

    # Set custom attributes if provided
    if params[:subscriber][:custom_attributes].present?
      custom_attrs = {}
      params[:subscriber][:custom_attributes].each do |key, value|
        custom_attrs[key] = value if value.present?
      end
      @subscriber.custom_attributes = custom_attrs
    end

    # Set defaults
    @subscriber.source ||= "manual"
    @subscriber.status ||= "active"
    @subscriber.confirmed_at ||= Time.current if @subscriber.status == "active"

    if @subscriber.save
      # Add to lists if specified
      if params[:subscriber][:list_ids].present?
        params[:subscriber][:list_ids].reject(&:blank?).each do |list_id|
          list = current_account.lists.find(list_id)
          list.add_subscriber(@subscriber)
        end
      end

      redirect_to @subscriber, notice: "Subscriber was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /subscribers/:id/edit
  def edit
    @lists = current_account.lists
  end

  # PATCH/PUT /subscribers/:id
  def update
    @lists = current_account.lists

    # Update attributes
    @subscriber.assign_attributes(subscriber_params.except(:email, :list_ids, :custom_attributes))

    # Update custom attributes if provided
    if params[:subscriber][:custom_attributes].present?
      custom_attrs = @subscriber.custom_attributes || {}
      params[:subscriber][:custom_attributes].each do |key, value|
        if value.present?
          custom_attrs[key] = value
        else
          custom_attrs.delete(key)
        end
      end
      @subscriber.custom_attributes = custom_attrs
    end

    if @subscriber.save
      # Update list subscriptions if specified
      if params[:subscriber][:list_ids].present?
        new_list_ids = params[:subscriber][:list_ids].reject(&:blank?).map(&:to_i)
        current_list_ids = @subscriber.list_subscriptions.where(status: "active").pluck(:list_id)

        # Remove from lists not in the new list
        (current_list_ids - new_list_ids).each do |list_id|
          list = current_account.lists.find(list_id)
          list.remove_subscriber(@subscriber)
        end

        # Add to new lists
        (new_list_ids - current_list_ids).each do |list_id|
          list = current_account.lists.find(list_id)
          list.add_subscriber(@subscriber)
        end
      end

      redirect_to @subscriber, notice: "Subscriber was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /subscribers/:id
  def destroy
    @subscriber.destroy
    redirect_to subscribers_url, notice: "Subscriber was successfully deleted."
  end

  # GET /subscribers/import
  def import
    @lists = current_account.lists
  end

  # POST /subscribers/import_csv
  def import_csv
    unless params[:file].present?
      redirect_to import_subscribers_path, alert: "Please select a CSV file to upload."
      return
    end

    require 'csv'

    file = params[:file]
    list_id = params[:list_id]

    @results = {
      success_count: 0,
      update_count: 0,
      error_count: 0,
      errors: []
    }

    begin
      CSV.foreach(file.path, headers: true, header_converters: :symbol) do |row|
        email = row[:email]&.strip&.downcase

        unless email.present?
          @results[:error_count] += 1
          @results[:errors] << "Row #{row.line_number}: Missing email address"
          next
        end

        # Find or create subscriber
        subscriber = current_account.subscribers.find_or_initialize_by(email: email)
        is_new = subscriber.new_record?

        # Set attributes from CSV
        subscriber.status = row[:status]&.downcase || "active"
        subscriber.source = "csv_import"
        subscriber.confirmed_at = Time.current if subscriber.status == "active" && subscriber.confirmed_at.nil?

        # Handle custom attributes
        custom_attrs = subscriber.custom_attributes || {}
        row.headers.each do |header|
          next if [:email, :status].include?(header)
          value = row[header]
          custom_attrs[header.to_s] = value if value.present?
        end
        subscriber.custom_attributes = custom_attrs

        if subscriber.save
          # Add to list if specified
          if list_id.present?
            list = current_account.lists.find(list_id)
            list.add_subscriber(subscriber)
          end

          if is_new
            @results[:success_count] += 1
          else
            @results[:update_count] += 1
          end
        else
          @results[:error_count] += 1
          @results[:errors] << "Row #{row.line_number} (#{email}): #{subscriber.errors.full_messages.join(', ')}"
        end
      end

      @lists = current_account.lists
      render :import_results
    rescue CSV::MalformedCSVError => e
      redirect_to import_subscribers_path, alert: "Invalid CSV file: #{e.message}"
    rescue => e
      redirect_to import_subscribers_path, alert: "Error processing CSV: #{e.message}"
    end
  end

  # GET /subscribers/suppressed
  def suppressed
    @suppressed_subscribers = current_account.subscribers.suppressed.order(created_at: :desc)

    # Paginate (50 per page for suppression list)
    @suppressed_subscribers = @suppressed_subscribers.limit(50).offset((params[:page].to_i - 1) * 50)
    @total_count = current_account.subscribers.suppressed.count
  end

  # POST /subscribers/:id/reactivate
  def reactivate
    @subscriber = current_account.subscribers.find(params[:id])

    if @subscriber.reactivate!
      redirect_to @subscriber, notice: "Subscriber was successfully reactivated."
    else
      redirect_to @subscriber, alert: "Failed to reactivate subscriber."
    end
  end

  private

  def set_subscriber
    @subscriber = current_account.subscribers.find(params[:id])
  end

  def subscriber_params
    params.require(:subscriber).permit(:email, :status, :source, list_ids: [])
  end

  def current_account
    @current_account ||= current_user.account
  end
  helper_method :current_account
end
