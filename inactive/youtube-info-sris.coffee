# Metadata lookup for youtube links
#
# <youtube link> - returns info about the link
#

module.exports = (robot) ->
  robot.hear youtube.link, (msg) ->
    msg.http(youtube.uri msg.match[1]).get() (err, res, body) ->
      if res.statusCode is 200
        data = JSON.parse(body)
        msg.send "Youtube: #{data.entry.title["$t"]}"

youtube =
  link: /(?:youtu\.be\/|youtube.com\/(?:watch\?.*\bv=|embed\/|v\/)|ytimg\.com\/vi\/)(.+?)(?:[^-a-zA-Z0-9]|$)/

  uri: (vid) -> "https://gdata.youtube.com/feeds/api/videos/#{vid}?v=2&alt=json"