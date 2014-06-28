Map = require "./Map"
_ = require "underscore"

class World

  mapsArray: ['Norkos']
  maps: {}

  constructor: ->
    _.forEach @mapsArray, (map) =>
      @maps[map] = new Map map

module.exports = exports = World