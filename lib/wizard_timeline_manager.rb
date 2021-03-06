# frozen_string_literal: true
require "#{Rails.root}/lib/course_meetings_manager"

# Routines for building and saving a course timeline after submission of wizard data
class WizardTimelineManager
  ###############
  # Entry point #
  ###############

  def self.update_timeline_and_tags(course, wizard_id, wizard_params)
    new(course, wizard_id, wizard_params).update_timeline_and_tags
  end

  #############
  # Main flow #
  #############

  def initialize(course, wizard_id, wizard_params)
    @course = course
    @output = wizard_params['wizard_output']['output'] || []
    @logic = wizard_params['wizard_output']['logic'] || []
    @tags = wizard_params['wizard_output']['tags'] || []

    # Load the wizard content building blocks.
    content_path = "#{Rails.root}/config/wizard/#{wizard_id}/content.yml"
    @all_content = YAML.load_file(content_path)

    @timeline = []
  end

  def update_timeline_and_tags
    # Parse the submitted wizard data and collect selected content.
    # @output is an array of strings that corresponds to the available
    # output options in @all_content.
    content_groups = @output.map do |content_key|
      @all_content[content_key]
    end

    # Build a timeline array
    build_timeline(content_groups)

    # Create and save week/block objects based on the object generated above
    save_timeline

    # Save any tags that have been generated from this Wizard output
    add_tags
  end

  ###################
  # Private methods #
  ###################

  private

  def build_timeline(content_groups)
    available_weeks = CourseMeetingsManager.new(@course).open_weeks
    return if available_weeks.zero?
    @timeline = initial_weeks_and_weights(content_groups)
    shorten_timeline_by_one_week until @timeline.size <= available_weeks
  end

  def initial_weeks_and_weights(content_groups)
    content_groups.flatten.map do |week|
      OpenStruct.new(weight: week['weight'],
                     blocks: week['blocks'])
    end
  end

  # Find the two consecutive weeks with the lowest total weight, and combine
  # then into a single week. This assumes at least two weeks in the timeline.
  def shorten_timeline_by_one_week
    week_pair_weights = {}
    i = 0
    @timeline.each_cons(2) do |week_pair|
      week_pair_weights[i] = week_pair[0][:weight] + week_pair[1][:weight]
      i += 1
    end

    lightest_weeks_index = week_pair_weights.min_by { |_first_week_index, weight| weight }[0]
    squish_consecutive_weeks(lightest_weeks_index)
  end

  def squish_consecutive_weeks(first_week_index)
    second_week_index = first_week_index + 1
    @timeline[first_week_index][:weight] += @timeline[second_week_index][:weight]
    @timeline[first_week_index][:blocks] += @timeline[second_week_index][:blocks]

    @timeline.delete_at(second_week_index)
  end

  def save_timeline
    @timeline.each_with_index do |week, week_index|
      next if week[:blocks].blank?
      week_record = Week.create(course_id: @course.id, order: week_index + 1)

      week[:blocks].each_with_index do |block, block_index|
        # Skip blocks with unmet 'if' dependencies
        next unless if_dependencies_met?(block)
        block['week_id'] = week_record.id
        block['order'] = block_index + 1
        save_block_and_gradeable(block)
      end
    end
  end

  def if_dependencies_met?(block)
    if_met = !block.key?('if')
    if_met ||= Array.wrap(block['if']).reduce(true) do |met, dep|
      met && @logic.include?(dep)
    end
    if_met
  end

  def save_block_and_gradeable(block)
    attr_keys_to_skip = %w(if graded points)
    block_params = block.except(*attr_keys_to_skip)
    block_record = Block.create(block_params)

    return unless block['graded']

    gradeable_params = { gradeable_item_id: block_record.id,
                         points: block['points'] || 10,
                         gradeable_item_type: 'block',
                         title: '' }
    gradeable = Gradeable.create(gradeable_params)
    block_record.update(gradeable_id: gradeable.id)
  end

  def add_tags
    @tags.each do |tag|
      # Only one tag for each tag key is allowed. Overwrite the previous tag if
      # one with the same key already exists, so that if a given choice is made
      # a second time, the tag gets updated to reflect the new choice.
      if Tag.exists?(course_id: @course.id, key: tag[:key])
        tag_model = Tag.find_by(course_id: @course.id, key: tag[:key])
        tag_model.update(tag: tag[:tag])
      else
        Tag.create(course_id: @course.id, tag: tag[:tag], key: tag[:key])
      end
    end
  end
end
