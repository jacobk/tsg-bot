# See if we can find links on reddit, and respond with title if found
#
# <url> - returns info about the link
#

module.exports = (robot) ->

  reddit = new Reddit robot

  robot.hear Reddit.MATCH_LINK, (msg) ->
    reddit.lookup msg.match[1], msg


class Reddit

    @SEARCH_API = "http://api.reddit.com/api/info"
    @MATCH_LINK =   # http://daringfireball.net/2010/07/improved_regex_for_matching_urls
       /// \b (
        (?: https?://                  # http or https
          | www\d{0,3}[.]              # "www.", "www1.", "www2." … "www999."
          | [a-z0-9.\-]+[.][a-z]{2,4}/ # looks like domain name followed by a slash
        )
        (?: [^\s()<>]+                          # Run of non-space, non-()<>
          | \(([^\s()<>]+|(\([^\s()<>]+\)))*\)  # balanced parens, up to 2 levels
        )+
        (?: \(([^\s()<>]+|(\([^\s()<>]+\)))*\)  # balanced parens, up to 2 levels
          | [^\s`!()\[\]{};:'".,<>?«»“”‘’]      # not a space or one of these punct chars
        )
      ) ///

    constructor: (@robot) ->

    lookup: (url, msg) ->
      options =
        url: url
        limit: 1

      @robot.http(Reddit.SEARCH_API)
        .query(options)
        .header("User-Agent","super happy bukkake bot v1.0 by /u/inferno")
        .header("Accept", "*/*")
        .get() (err, resp, body) ->
          body = JSON.parse body
          if body?.data?.children.length
            item_data = body.data.children[0].data
            msg.send "Reddit: #{item_data.title} (/r/#{item_data.subreddit})"

