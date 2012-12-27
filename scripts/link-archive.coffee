# Description:
#   Keep track of links
#
# Dependencies:
#   None
#
# Configuration:
#   None
#
# Commands:
#   None
#
# Author:
#   jacobk


# TODO
# * Figure out how to properly check content (hash)
#   - perhaps only usable for images
# * Make it possible to post link you know is old
# * List last links
# * List most posed links
# * Test if a link has been posted before

Crypto = require "crypto"

version = "1"

module.exports = (robot) ->
  
  # wait for brain to load, merging doesn't work
  robot.brain.on "loaded", ->
    robot.brain.data.links ?= {}
    unless robot.brain.data.links.version is version
      console.log "Migrating to #{version}"
      robot.brain.data.links.version = version
      robot.brain.save()
 
  robot.hear link.pattern, (msg) ->
    url  = link.normalize msg.match[1]
    nick = msg.message.user.name

    post = [nick, new Date().getTime().toString()]

    hash = link.md5hash url
    links = robot.brain.data.links

    posts = links[hash] ?= {url: url, posters: []}
    posts.posters.push post
    [firstNick, firstTime] = posts.posters[0]

    if firstNick and firstNick isnt nick
      msg.reply "OLD! #{firstNick} posted it #{new Date(parseInt(firstTime))}"
    robot.brain.save()

link =
  md5hash: (data) ->
    md5sum = Crypto.createHash('md5');
    md5sum.update(new Buffer(data))
    md5sum.digest("hex").substring(0,8)

  # http://daringfireball.net/2010/07/improved_regex_for_matching_urls
  pattern: /// \b (
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

  # Very basic normalization for now
  normalize: (url) ->
    uriPattern = new RegExp "^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?"
    [_, _, scheme, _, authority, path, _, query, _, fragment] = url.match uriPattern
    unless scheme
      return @normalize "http://#{url}"
    scheme = scheme.toLowerCase()
    scheme = scheme.substr(0,4)
    authority = authority.toLowerCase()
    authorityParts = authority.split(":")
    if authorityParts[1] is "80"
      authority = authorityParts[0]
    path = "/" unless path
    query = "?#{query}" if query
    fragment = "##{fragment}" if fragment
    "#{scheme}://#{authority}#{path}#{query or ""}#{fragment or ""}"