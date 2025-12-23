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
