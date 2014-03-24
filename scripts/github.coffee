# Misc github integrations
#
# request <label> <desc> - Create an issue
#

GitHubApi = require("github")

github_access_token = process.env.GITHUB_ACCESS_TOKEN

module.exports = (robot) ->
  github = new GitHubApi(version: "3.0.0")
  github.authenticate
    type: "oauth",
    token: github_access_token

  robot.respond /request (bug|feature) (.+)/i, (msg) ->
    title = msg.match[2]
    label = msg.match[1]
    github.issues.create
      user: "jacobk"
      repo: "tsg-bot"
      title: "[#{msg.message.user.name}] #{title}"
      labels: [label],
      (err, res) =>
        unless err
          msg.reply "Got it! #{res.html_url}"
        else
          msg.reply "Failed to create issue"
