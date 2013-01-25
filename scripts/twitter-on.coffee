# Description:
#   Display a random popular tweet about a subject
#
# Dependencies:
#   None
#
# Configuration:
#   None
#
# Commands:
#   hubot <keyword> on twitter - Returns a tweet about <keyword>
#
# Author:
#   frekey

module.exports = (robot) ->
  robot.respond /twitter on (.+)$/i, (msg) ->
    search = escape(msg.match[1])
    options =
      q: search
      result_type: 'popular'

    msg.http('http://search.twitter.com/search.json')
      .query(options)
      .get() (err, res, body) ->
        tweets = JSON.parse(body)

        if tweets.results? and tweets.results.length > 0
          tweet  = msg.random tweets.results
          msg.send "@#{tweet.from_user}: #{tweet.text}"
        else
          msg.send "No one is tweeting about that."
