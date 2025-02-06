require_relative './lib/client'
require_relative './lib/pull_request'
require 'csv'

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

class DirectReviewAnalyzer
  def initialize
    @client = Client.new
  end

  def analyze(username)
    puts "Analyzing #{username}"
    raw_prs = @client.fetch_all_prs_direct_reviews(username)
    prs = raw_prs.map { |pr_data| PullRequest.new(pr_data) }
    
    relevant_prs = prs.reject { |pr| pr.data.dig('author', 'login') == username }
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

  def analyze_all(usernames)
    results = usernames.map { |username| analyze(username) }
    export_to_csv(results)
    print_results(results)
    results
  end

  private

  def calculate_timing_metrics(relevant_prs, merged_prs, username)
    review_times = relevant_prs.map { |pr| 
      if pr.engaged_by?(username)
        business_hours_between(pr.review_requested_at(username), pr.first_engagement_at(username))
      end
    }.compact
  
    approval_times = merged_prs.map { |pr| 
      if pr.approved_by?(username)
        business_hours_between(pr.review_requested_at(username), pr.first_approval_at(username))
      end
    }.compact
   
    merge_times = merged_prs.select { |pr| pr.engaged_by?(username) }.map { |pr| 
      business_hours_between(pr.review_requested_at(username), pr.merged_at)
    }.compact
  
    {
      review_turnaround: {
        average: calculate_average(review_times),
        p90: calculate_percentile(review_times, 90)
      },
      approval_turnaround: {
        average: calculate_average(approval_times),
        p90: calculate_percentile(approval_times, 90)
      },
      time_to_merge: {
        average: calculate_average(merge_times),
        p90: calculate_percentile(merge_times, 90)
      }
    }
  end

  def export_to_csv(results)
    CSV.open("direct_review_metrics.csv", "wb") do |csv|
      csv << [
        "Username",
        "Total PRs",
        "Engaged PRs",
        "Engagement Rate",
        "Approved PRs",
        "Approval Rate",
        "Avg Review Turnaround",
        "P90 Review Turnaround",
        "Avg Approval Turnaround",
        "P90 Approval Turnaround",
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
          metrics[:timing][:approval_turnaround][:average],
          metrics[:timing][:approval_turnaround][:p90],
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
      puts "Approval Turnaround: avg #{metrics[:timing][:approval_turnaround][:average]}h, p90 #{metrics[:timing][:approval_turnaround][:p90]}h"
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
end

if __FILE__ == $PROGRAM_NAME
  analyzer = DirectReviewAnalyzer.new
  analyzer.analyze_all(GITHUB_USERNAMES)
end