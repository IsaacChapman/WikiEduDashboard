# frozen_string_literal: true
require "#{Rails.root}/lib/word_count"

#= Presenter for courses / campaign view
class CoursesPresenter
  attr_reader :current_user, :campaign_param

  def initialize(current_user, campaign_param)
    @current_user = current_user
    @campaign_param = campaign_param
  end

  def user_courses
    return unless current_user
    current_user.courses.current_and_future
  end

  def campaign
    return NullCampaign.new if campaign_param == 'none'
    @campaign ||= Campaign.find_by(slug: campaign_param)
    raise NoCampaignError if @campaign.nil? && campaign_param == ENV['default_campaign']
    @campaign
  end

  def courses
    campaign.courses
  end

  def courses_by_recent_edits
    # Sort first by recent edit count, and then by course title
    courses.sort_by { |course| [-course.recent_revision_count, course.title] }
  end

  def word_count
    WordCount.from_characters courses.sum(:character_sum)
  end

  def course_string_prefix
    Features.default_course_string_prefix
  end

  def uploads_in_use_count
    @uploads_in_use_count ||= courses.sum(:uploads_in_use_count)
    @uploads_in_use_count
  end

  def upload_usage_count
    @upload_usage_count ||= courses.sum(:upload_usages_count)
    @upload_usage_count
  end

  class NoCampaignError < StandardError; end
end

#= Pseudo-Campaign that displays all unsubmitted, non-deleted courses
class NullCampaign
  def title
    I18n.t('courses.unsubmitted')
  end

  def slug
    'none'
  end

  def courses
    Course.unsubmitted.order(created_at: :desc)
  end

  def students_without_nonstudents
    []
  end

  def trained_percent
    0
  end
end
