class TeamMembersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_team_management_permission!

  def index
    @team_members = current_account.users.order(created_at: :asc)
    @pending_invitations = current_account.invitations.pending.order(created_at: :desc)
  end

  def update
    @user = current_account.users.find(params[:id])

    # Prevent changing own role
    if @user == current_user
      redirect_to team_members_path, alert: "You cannot change your own role."
      return
    end

    # Only owners can change roles
    unless current_user.owner?
      redirect_to team_members_path, alert: "Only account owners can change user roles."
      return
    end

    if @user.update(user_params)
      redirect_to team_members_path, notice: "Team member role updated successfully."
    else
      redirect_to team_members_path, alert: "Failed to update team member."
    end
  end

  def destroy
    @user = current_account.users.find(params[:id])

    # Prevent deleting yourself
    if @user == current_user
      redirect_to team_members_path, alert: "You cannot remove yourself from the team."
      return
    end

    # Prevent deleting the owner
    if @user.owner?
      redirect_to team_members_path, alert: "Cannot remove the account owner."
      return
    end

    @user.destroy
    redirect_to team_members_path, notice: "Team member removed successfully."
  end

  private

  def user_params
    params.require(:user).permit(:role)
  end

  def require_team_management_permission!
    unless current_user.can_manage_team?
      redirect_to "/dashboard", alert: "You don't have permission to manage team members."
    end
  end

  def current_account
    @current_account ||= current_user.account
  end
  helper_method :current_account
end
