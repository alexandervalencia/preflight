module PullRequestsHelper
  FileViewState = Data.define(:label, :css_class, :action_label)

  def comment_target_for(line)
    return ["left", line.old_number] if line.type == :deletion
    return ["right", line.new_number] if line.new_number.present?

    [nil, nil]
  end

  def diff_line_class(line)
    "diff-line diff-line--#{line.type}"
  end

  def file_view_state(pull_request, viewed_file)
    return FileViewState.new(label: "Unviewed", css_class: "view-state--unviewed", action_label: "Mark as viewed") unless viewed_file
    return FileViewState.new(label: "Viewed", css_class: "view-state--viewed", action_label: nil) if viewed_file.current?(repository: pull_request.git_repository)

    FileViewState.new(label: "New changes", css_class: "view-state--new", action_label: "Mark as viewed again")
  end
end
