require_relative './lib/client'
require_relative './lib/pull_request'
require 'csv'
require 'pry'
TEAM_NAME = "Shopify/payments-infrastructure"

GITHUB_USERNAMES = %w[
  Smittttty
  abalmeida7
  Anasshahidd21
  Wryte
  indominus-joe
  nSanjari
  nicholashhchen
  owenlintonAD
].freeze

class TeamReviewAnalyzer
  DEFAULT_PR_LIMIT = 500

  def initialize(pr_limit = DEFAULT_PR_LIMIT)
    @client = Client.new
    @pr_limit = pr_limit
    @prs = nil
  end

  def analyze_all(usernames)
    puts "\nFetching team review data..."
    fetch_team_prs
    
    puts "\nAnalyzing data for each user..."
    results = usernames.map { |username| analyze(username) }
    
    puts "\nExporting results to CSV..."
    export_to_csv(results)
    
    puts "\nResults:"
    print_results(results)
    results
  end

  private

  def get_engagement_type(pr, username)
    types = []
    types << "Review" if pr.data.dig('reviews', 'nodes')&.any? { |review| review.dig('author', 'login') == username }
    types << "Comment" if pr.data.dig('comments', 'nodes')&.any? { |comment| comment.dig('author', 'login') == username }
    types << "Thread Comment" if pr.data.dig('reviewThreads', 'nodes')&.any? { |thread| 
      thread.dig('comments', 'nodes')&.any? { |comment| comment.dig('author', 'login') == username }
    }
    types << "Approval" if pr.approved_by?(username)
    
    types.empty? ? "None" : types.join(", ")
  end

  def fetch_team_prs
    raw_prs = @client.fetch_team_tagged_prs(TEAM_NAME)
    @prs = raw_prs.map { |pr_data| PullRequest.new(pr_data) }
    dump_prs_to_file(@prs)
  end

  def analyze(username)
    puts "Analyzing metrics for #{username}..."
    
    relevant_prs = @prs.reject { |pr| pr.data.dig('author', 'login') == username }
    merged_prs = relevant_prs.select(&:merged?)
    
    engaged_prs = relevant_prs.select { |pr| pr.engaged_by?(username) }
    approved_prs = merged_prs.select { |pr| pr.approved_by?(username) }

    {
      username: username,
      metrics: {
        total_prs: relevant_prs.count,
        engagement: {
          count: engaged_prs.count,
          rate: calculate_percentage(engaged_prs.count, relevant_prs.count)
        },
        approvals: {
          count: approved_prs.count,
          rate: calculate_percentage(approved_prs.count, merged_prs.count)
        },
        timing: calculate_timing_metrics(relevant_prs, merged_prs, username)
      }
    }
  end

  def calculate_timing_metrics(relevant_prs, merged_prs, username)
    puts "\nDetailed timing analysis for #{username}:"
    
    review_times = relevant_prs.map { |pr| 
      if pr.engaged_by?(username)
        request_time = pr.team_review_requested_at
        engagement_time = pr.first_engagement_at(username)
        
        business_hours_between(request_time, engagement_time)
      end
    }.compact
  
    merge_times = merged_prs.select { |pr| pr.engaged_by?(username) }.map { |pr| 
      request_time = pr.team_review_requested_at
      merge_time = pr.merged_at
      
      business_hours_between(request_time, merge_time)
    }.compact
  
    {
      review_turnaround: {
        average: calculate_average(review_times),
        p90: calculate_percentile(review_times, 90)
      },
      time_to_merge: {
        average: calculate_average(merge_times),
        p90: calculate_percentile(merge_times, 90)
      }
    }
  end

  def export_to_csv(results)
    CSV.open("team_review_metrics.csv", "wb") do |csv|
      csv << [
        "Username",
        "Total PRs",
        "Engaged PRs",
        "Engagement Rate",
        "Approved PRs",
        "Approval Rate",
        "Avg Review Turnaround",
        "P90 Review Turnaround",
        "Avg Time to Merge",
        "P90 Time to Merge"
      ]

      results.each do |result|
        metrics = result[:metrics]
        csv << [
          result[:username],
          metrics[:total_prs],
          metrics[:engagement][:count],
          "#{metrics[:engagement][:rate]}%",
          metrics[:approvals][:count],
          "#{metrics[:approvals][:rate]}%",
          metrics[:timing][:review_turnaround][:average],
          metrics[:timing][:review_turnaround][:p90],
          metrics[:timing][:time_to_merge][:average],
          metrics[:timing][:time_to_merge][:p90]
        ]
      end
    end
  end

  def print_results(results)
    results.each do |result|
      metrics = result[:metrics]
      puts "\n#{result[:username]}:"
      puts "Total PRs: #{metrics[:total_prs]}"
      puts "Engagement: #{metrics[:engagement][:count]}/#{metrics[:total_prs]} (#{metrics[:engagement][:rate]}%)"
      puts "Approvals: #{metrics[:approvals][:count]} of #{metrics[:total_prs]} merged PRs (#{metrics[:approvals][:rate]}%)"
      puts "Review Turnaround: avg #{metrics[:timing][:review_turnaround][:average]}h, p90 #{metrics[:timing][:review_turnaround][:p90]}h"
      puts "Time to Merge: avg #{metrics[:timing][:time_to_merge][:average]}h, p90 #{metrics[:timing][:time_to_merge][:p90]}h"
    end
  end

  def calculate_percentage(numerator, denominator)
    return 0.0 if denominator.zero?
    (numerator.to_f / denominator * 100).round(2)
  end

  def calculate_average(values)
    return 0.0 if values.empty?
    (values.sum / values.length).round(2)
  end

  def calculate_percentile(values, percentile)
    return 0.0 if values.empty?
    sorted = values.sort
    k = (percentile / 100.0 * (sorted.length - 1)).round
    sorted[k].round(2)
  end

  def business_hours_between(start_time, end_time)
    return nil unless start_time && end_time
    
    business_hours = 0
    current_time = start_time
  
    while current_time < end_time
      if current_time.wday != 0 && current_time.wday != 6
        if current_time.hour.between?(9, 16)
          business_hours += 1
        end
      end
      current_time += 3600
    end
  
    business_hours.round(2)
  end

  def dump_prs_to_file(prs, filename = "pr_data_dump.txt")
    File.open(filename, "w") do |file|
      file.puts "PR Data Dump - #{Time.now}"
      file.puts "Total PRs: #{prs.count}"
      file.puts "=" * 80
      
      prs.each do |pr|
        file.puts "\nPR ##{pr.data['number']}"
        file.puts "-" * 40
        
        file.puts "URL: #{pr.data['url']}"
        file.puts "State: #{pr.data['state']}"
        file.puts "Created At: #{pr.data['createdAt']}"
        file.puts "Merged At: #{pr.data['mergedAt'] || 'Not merged'}"
        file.puts "Author: #{pr.data.dig('author', 'login')}"
        
        file.puts "\nReview Requests:"
        pr.data.dig('reviewRequests', 'nodes')&.each do |request|
          reviewer = request.dig('requestedReviewer', 'name') || request.dig('requestedReviewer', 'login')
          file.puts "  - #{reviewer}" if reviewer
        end
        
        file.puts "\nReviews:"
        pr.data.dig('reviews', 'nodes')&.each do |review|
          file.puts "  - Author: #{review.dig('author', 'login')}"
          file.puts "    State: #{review['state']}"
          file.puts "    Created At: #{review['createdAt']}"
        end
        
        file.puts "\nComments:"
        pr.data.dig('comments', 'nodes')&.each do |comment|
          file.puts "  - Author: #{comment.dig('author', 'login')}"
          file.puts "    Created At: #{comment['createdAt']}"
        end
        
        file.puts "\nReview Thread Comments:"
        pr.data.dig('reviewThreads', 'nodes')&.each_with_index do |thread, i|
          file.puts "  Thread #{i + 1}:"
          thread.dig('comments', 'nodes')&.each do |comment|
            file.puts "    - Author: #{comment.dig('author', 'login')}"
            file.puts "      Created At: #{comment['createdAt']}"
          end
        end
        
        file.puts "\n" + "=" * 80
      end
    end
    
    puts "PR data dumped to #{filename}"
  end
end

if __FILE__ == $PROGRAM_NAME
  pr_limit = ENV['PR_LIMIT']&.to_i || 500
  analyzer = TeamReviewAnalyzer.new(pr_limit)
  analyzer.analyze_all(GITHUB_USERNAMES)
end