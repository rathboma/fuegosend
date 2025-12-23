class SegmentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_segment, only: [:show, :edit, :update, :destroy]

  # GET /segments
  def index
    @segments = current_account.segments.includes(:list).order(created_at: :desc)

    # Filter by list
    if params[:list_id].present?
      @segments = @segments.where(list_id: params[:list_id])
    end
  end

  # GET /segments/:id
  def show
    # Refresh count if stale
    @segment.refresh_count! if @segment.count_stale?

    # Get sample of matching subscribers (first 10)
    @sample_subscribers = @segment.matching_subscribers.limit(10)
  end

  # GET /segments/new
  def new
    @segment = current_account.segments.new
    @lists = current_account.lists
  end

  # POST /segments
  def create
    @segment = current_account.segments.new(segment_params)
    @lists = current_account.lists

    if @segment.save
      @segment.refresh_count!
      redirect_to @segment, notice: "Segment was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /segments/:id/edit
  def edit
    @lists = current_account.lists
  end

  # PATCH/PUT /segments/:id
  def update
    @lists = current_account.lists

    if @segment.update(segment_params)
      @segment.refresh_count!
      redirect_to @segment, notice: "Segment was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /segments/:id
  def destroy
    if @segment.campaigns.exists?
      redirect_to @segment, alert: "Cannot delete segment that is being used by campaigns."
    else
      @segment.destroy
      redirect_to segments_url, notice: "Segment was successfully deleted."
    end
  end

  private

  def set_segment
    @segment = current_account.segments.find(params[:id])
  end

  def segment_params
    params.require(:segment).permit(
      :name,
      :description,
      :list_id,
      criteria: []
    )
  end

  def current_account
    @current_account ||= current_user.account
  end
  helper_method :current_account
end
