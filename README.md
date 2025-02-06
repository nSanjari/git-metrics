# Setup

## Setup local Ruby environment

``` 
brew install rbenv
rbenv local 3.3.0
ruby -v # should show 3.3.0
```

## Install dependencies

```
bundle install
```

## Install GitHub CLI

```
brew install gh
gh auth login
```

## Run the script

```
# Run direct review analysis
ruby direct_review_analysis.rb

# Run team review analysis
ruby team_review_analysis.rb

# Run overall metrics analysis
ruby overall_metrics_analysis.rb
```

# PR Review Analytics

Tool to analyze PR review patterns and metrics for the payments-infrastructure team.

## Metrics Calculation

### Direct Review Metrics
- **Engagement Rate**: `(engaged_prs / total_prs) * 100`
  - Counts PRs where user left comments, reviews, or thread comments
  - Excludes PRs where user is the author

- **Approval Rate**: `(approved_merged_prs / total_merged_prs) * 100`
  - Only considers merged PRs
  - Counts PRs where user gave explicit approval

- **Review Turnaround**: Time between review request and first engagement
  - Measured in business hours (9am-5pm, excluding weekends)
  - Reports both average and 90th percentile

- **Approval Turnaround**: Time between review request and approval
  - Only counts explicit approvals
  - Measured in business hours

- **Time to Merge**: Time between review request and merge
  - Only for merged PRs
  - Measured in business hours

### Team Review Metrics
Similar to direct review metrics but considers team-tagged PRs:
- Uses PR creation time as start time for team requests
- Tracks engagement from all team members
- Same business hour calculations

### Overall Team Metrics
- **Unique PRs**: Count of distinct PRs with at least one team review
- **First Review Time**: Time to first team member engagement
- **Second Review Time**: Time to second team member engagement
- **Review Distribution**: 
  - 1 review: `(single_review_prs / total_merged_prs) * 100`
  - 2 reviews: `(double_review_prs / total_merged_prs) * 100`
  - 2+ reviews: `(multi_review_prs / total_merged_prs) * 100`

### Common Calculations
- **Business Hours**: 9am-5pm, excluding weekends
- **Averages**: Mean of all values, rounded to 2 decimals
- **P90**: 90th percentile value from sorted array
