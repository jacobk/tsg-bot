# Metadata lookup for IMDb links
#
# <IMDb link> - returns info about the link
#

module.exports = (robot) ->
  robot.hear imdb.link, (msg) ->
    msg.http(imdb.url msg.match[1]).get() (err, res, body) ->
      if res.statusCode is 200
        data = JSON.parse(body)
        msg.send imdb.format data

imdb =
  link: /imdb.com\/title\/(tt\d+)/i

  # Use OMDBAPI for now
  url: (movide_id) -> "http://www.omdbapi.com/?i=#{movide_id}"

  format: (data) ->
    fields = ["imdbRating", "Year", "Director", "Genre"]
    "IMDb: #{data.Title} (#{(data[f] for f in fields).join(" / ")})"