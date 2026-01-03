class InvitationsController < ApplicationController
  before_action :authenticate_user!, except: [:accept, :process_acceptance]
  before_action :require_team_management_permission!, only: [:create, :destroy]
  before_action :set_invitation_by_token, only: [:accept, :process_acceptance]

  def create
    @invitation = current_account.invitations.new(invitation_params)
    @invitation.invited_by = current_user

    if @invitation.save
      # Send invitation email
      InvitationMailer.invite(@invitation).deliver_later
      redirect_to team_members_path, notice: "Invitation sent to #{@invitation.email}"
    else
      redirect_to team_members_path, alert: "Failed to send invitation: #{@invitation.errors.full_messages.join(', ')}"
    end
  end

  def destroy
    @invitation = current_account.invitations.find(params[:id])
    @invitation.destroy
    redirect_to team_members_path, notice: "Invitation cancelled."
  end

  # Public action - no authentication required
  def accept
    unless @invitation.valid_for_acceptance?
      if @invitation.expired?
        render :expired and return
      else
        redirect_to root_path, alert: "This invitation has already been accepted." and return
      end
    end

    @user = User.new(email: @invitation.email)
  end

  # Public action - no authentication required
  def process_acceptance
    unless @invitation.valid_for_acceptance?
      redirect_to root_path, alert: "Invalid or expired invitation." and return
    end

    user = @invitation.accept!(
      first_name: params[:user][:first_name],
      last_name: params[:user][:last_name],
      password: params[:user][:password],
      password_confirmation: params[:user][:password_confirmation]
    )

    if user && user.persisted?
      sign_in(user)
      redirect_to "/dashboard", notice: "Welcome to #{user.account.name}! Your account has been created."
    else
      @user = user || User.new(email: @invitation.email)
      flash.now[:alert] = "Failed to create account: #{@user.errors.full_messages.join(', ')}"
      render :accept
    end
  end

  private

  def invitation_params
    params.require(:invitation).permit(:email, :role)
  end

  def set_invitation_by_token
    @invitation = Invitation.find_by!(token: params[:token])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Invitation not found."
  end

  def require_team_management_permission!
    unless current_user.can_manage_team?
      redirect_to "/dashboard", alert: "You don't have permission to manage invitations."
    end
  end

  def current_account
    @current_account ||= current_user.account
  end
  helper_method :current_account
end
