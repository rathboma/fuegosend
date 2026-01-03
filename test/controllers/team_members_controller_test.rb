require "test_helper"

class TeamMembersControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get team_members_index_url
    assert_response :success
  end

  test "should get create" do
    get team_members_create_url
    assert_response :success
  end

  test "should get destroy" do
    get team_members_destroy_url
    assert_response :success
  end
end
