
Character = require "./../base/Character"
RestrictedNumber = require "restricted-number"
MessageCreator = require "../../system/MessageCreator"
Constants = require "../../system/Constants"
Equipment = require "../../item/Equipment"
_ = require "underscore"
Personality = require "../base/Personality"

Chance = require "chance"
chance = new Chance()

class Player extends Character

  isBusy: false

  constructor: (player) ->
    super player

  initialize: ->
    if not @xp
      @xp = new RestrictedNumber 0, (@levelUpXpCalc 0), 0
      @gold = new RestrictedNumber 0, 9999999999, 0
      @levelUp()
      @x = 10
      @y = 10
      @map = 'Norkos'
      @changeProfession "Generalist"
      @generateBaseEquipment()

  generateBaseEquipment: ->
    @equipment = [
      new Equipment {type: "body",    class: "Newbie", name: "Tattered Shirt"}
      new Equipment {type: "feet",    class: "Newbie", name: "Cardboard Shoes"}
      new Equipment {type: "finger",  class: "Newbie", name: "Twisted Wire"}
      new Equipment {type: "hands",   class: "Newbie", name: "Pixelated Gloves"}
      new Equipment {type: "head",    class: "Newbie", name: "Miniature Top Hat"}
      new Equipment {type: "legs",    class: "Newbie", name: "A Leaf"}
      new Equipment {type: "neck",    class: "Newbie", name: "Old Brooch"}
      new Equipment {type: "mainhand",class: "Newbie", name: "Empty and Broken Ale Bottle"}
      new Equipment {type: "offhand", class: "Newbie", name: "Chunk of Rust"}
      new Equipment {type: "charm",   class: "Newbie", name: "Ancient Bracelet"}
    ]

  handleTrainerOnTile: (tile) ->
    return if @isBusy
    @isBusy = true
    className = tile.object.name
    message = "#{@name} has met with the #{className} trainer!"
    if @professionName is className
      message += " Alas, #{@name} is already a #{className}!"
      @isBusy = false
    else
      @playerManager.game.eventHandler.doYesNo {}, @, (result) =>
        @isBusy = false
        return if not result
        @changeProfession className

    @playerManager.game.broadcast MessageCreator.genericMessage message

  handleTeleport: (tile) ->
    dest = tile.object.properties
    dest.x = parseInt dest.x
    dest.y = parseInt dest.y

    if not dest.map
      console.error "ERROR. No dest.map at #{@x},#{@y} in #{@map}"
      return

    @map = dest.map
    @x = dest.x
    @y = dest.y

    message = ""

    switch dest.movementType
      when "ascend" then message = "#{@name} has ascended to #{dest.destName}."
      when "descend" then message = "#{@name} has descended to #{dest.destName}."

    @emit dest.movementType

    @playerManager.game.broadcast MessageCreator.genericMessage message

  handleTile: (tile) ->
    switch tile.object?.type
      when "Trainer" then @handleTrainerOnTile tile
      when "Teleport" then @handleTeleport tile

  moveAction: ->
    randomDir = -> chance.integer({min: 1, max: 9})
    dir = randomDir()
    dir = randomDir() while dir is @ignoreDir

    dir = if chance.bool {likelihood: 75} then @lastDir else dir
    newLoc = @num2dir dir, @x, @y

    tile = @playerManager.game.world.maps[@map].getTile newLoc.x,newLoc.y
    if not tile.blocked
      @x = newLoc.x
      @y = newLoc.y
      @lastDir = dir
      @ignoreDir = null

      @emit 'walk'
      @emit "on#{tile.terrain}"

    else
      @lastDir = null
      @ignoreDir = dir

      @emit 'hitWall'

    @handleTile tile

  changeProfession: (to) ->
    professionProto = require "./classes/#{to}"
    @profession = new professionProto()
    @professionName = professionProto.name
    @profession.load @
    @playerManager.game.broadcast MessageCreator.genericMessage "#{@name} is now a #{to}!"

  personalityReduce: (appFunctionName, args = [], defaultValue = 0) ->
    args = [args] if not _.isArray args
    array = []
      .concat if not _.isEmpty @profession then @profession else []
      .concat @personalities ? []
    _.reduce array, (combined, iter) ->
      console.log iter
      combined + iter[appFunctionName].apply iter, args
    , defaultValue


  calculateYesPercent: ->
    val = 50 + @personalityReduce 'calculateYesPercentBonus'
    val

  getGender: ->
    "male"

  rebuildPersonalityList: ->
    @personalities = _.map @personalityStrings, (personality) ->
      Personality::createPersonality personality

  addPersonality: (newPersonality) ->
    return no if not Personality::doesPersonalityExist newPersonality

    @personalityStrings.push newPersonality

    @personalities.push Personality::createPersonality newPersonality

    @personalities = _.uniq @personalities
    yes

  removePersonality: (oldPersonality) ->
    @personalityStrings = _.without @personalityStrings, oldPersonality
    @rebuildPersonalityList()
    yes

  possiblyDoEvent: ->
    event = Constants.pickRandomEvent @
    return if not event
    @playerManager.game.eventHandler.doEvent event, @, ->{} #god damned code collapse

  takeTurn: ->
    @moveAction()
    @possiblyDoEvent()
    @save()

  save: ->
    return if not @playerManager
    @playerManager.savePlayer @

  gainGold: (gold) ->
    @gold.add gold

  gainXp: (xp) ->
    if xp > 0
      @emit "gainXp"
    else
      @emit "loseXp"

    @xp.set 0 if _.isNaN @xp.__current
    @xp.add xp

    if @xp.atMax()
      @levelUp()

  levelUp: ->
    return if not @playerManager
    @playerManager.game.broadcast MessageCreator.genericMessage "#{@name} has attained level #{@level.getValue()}!"
    @level.add 1
    @hp.maximum += 10
    @mp.maximum += 5
    @xp.maximum = @levelUpXpCalc @level.getValue()
    @xp.toMinimum()
    @emit "levelUp"

  levelUpXpCalc: (level) ->
    Math.floor 100 + (400 * Math.pow level, 1.67)

module.exports = exports = Player