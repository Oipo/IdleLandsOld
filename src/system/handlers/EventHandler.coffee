chance = new (require "chance")()

_ = require "lodash"
_.str = require "underscore.string"

Datastore = require "./../database/DatabaseWrapper"
MessageCreator = require "./MessageCreator"
Constants = require "./../utilities/Constants"
Battle = require "../../event/Battle"
Q = require "q"

Party = require "../../event/Party"

requireDir = require "require-dir"
allEvents = requireDir "../../event/singles"

class EventHandler

  constructor: (@game) ->
    @playerEventsDb = new Datastore "playerEvents", (db) ->
      db.ensureIndex {createdAt: 1}, {expiresAfterSeconds: 7200}, ->

  doEventForPlayer: (playerName, eventType = null, isGuild = no) ->
    player = @game.playerManager.getPlayerByName playerName
    eventType = Constants.pickRandomNormalEventType(player) if not eventType
    if not player
      console.error "Attempting to do event #{eventType} for #{playerName}, but player was not there."
      return

    @doEvent eventType, player, isGuild

  doEvent: (eventType, player, isGuild = no) ->
    defer = Q.defer()
    @game.componentDatabase.getRandomEvent eventType, {expiredOn: {$exists: no}}, (e, event) =>
      @game.errorHandler.captureException e if e
      return if not event or not player

      try
        event = switch eventType
          when 'providence' then                          new allEvents.ProvidenceEvent @game, event, player
          when 'levelDown' then                           new allEvents.LevelDownEvent @game, event, player
          when 'blessXp', 'forsakeXp' then                new allEvents.XpEvent @game, event, player
          when 'blessXpParty', 'forsakeXpParty' then      new allEvents.XpPartyEvent @game, event, player
          when 'blessGold', 'forsakeGold' then            new allEvents.GoldEvent @game, event, player
          when 'blessGoldParty', 'forsakeGoldParty' then  new allEvents.GoldPartyEvent @game, event, player
          when 'blessItem', 'forsakeItem' then            new allEvents.ItemModEvent @game, event, player
          when 'findItem' then                            new allEvents.FindItemEvent @game, event, player
          when 'merchant' then                            new allEvents.MerchantEvent @game, event, player
          when 'party' then                               new allEvents.PartyEvent @game, event, player
          when 'enchant', 'tinker' then                   new allEvents.EnchantEvent @game, event, player
          when 'flipStat' then                            new allEvents.FlipStatEvent @game, event, player
          when 'battle' then                              new allEvents.MonsterBattleEvent @game, event, player
          when 'towncrier' then                           new allEvents.TownCrierEvent @game, event, player

        event?.isGuild = isGuild if isGuild and _.isBoolean isGuild
        event?.go()

      catch e
        @game.errorHandler.captureException e, extra: name: player.name, gear: player.equipment, inv: player.overflow

      player.recalculateStats()
      defer.resolve()

    defer.promise

  bossBattle: (player, bossName) ->
    return if @game.inBattle

    boss = @createBoss bossName
    return if not boss

    bossParty = new Party @game, boss

    @bossBattleParty player, bossParty, bossName

  bossPartyBattle: (player, bossPartyName) ->
    return if @game.bossFactory.cantDoBossPartyBattle bossPartyName
    monsters = @createBosses (@game.bossFactory.createBossPartyNames bossPartyName), bossPartyName

    try
      bossParty = new Party @game, monsters
    catch e
      @game.errorHandler.captureException e, extra: partyName: bossPartyName

    @bossBattleParty player, bossParty, bossPartyName

  createBoss: (bossName, partyName) ->
    @game.bossFactory.createBoss bossName, partyName

  createBosses: (bossNames, partyName) ->
    _.map bossNames, (bossName) => @createBoss bossName, partyName

  bossBattleParty: (player, bossParty, name) ->

    startBattle = =>
      _.each player.party.players, (member) ->
        member.x = player.x
        member.y = player.y
        member.map = player.map

        member?.resetBossTimer name

      _.each bossParty.players, (boss) ->
        boss.mirror player.party if boss.shouldMirror

      message = ">>> BOSS BATTLE: %player prepares for an epic battle against #{name}!"
      message = MessageCreator.doStringReplace message, player
      @game.broadcast MessageCreator.genericMessage message
      new Battle @game, [player.party, bossParty]

    # players need a party to get into combat
    if not player.party

      # we only give them an actual party if they're not too close to the bosses score
      if player.calc.totalItemScore() < bossParty.score() * 0.8
        @doEventForPlayer player.name, 'party'
        .then ->
          startBattle()
      else
        # otherwise they get a party of themselves
        new Party @game, [player]
        startBattle()

    else
      startBattle()

  # sendMessage = no implies that you're forwarding the original message to multiple people
  broadcastEvent: (options) ->
    {message, player, extra, sendMessage, type, link} = options
    sendMessage = yes if _.isUndefined sendMessage
    extra = {} unless extra

    # monsters can't receive messages :(
    return if player.isMonster

    if sendMessage
      message = MessageCreator.doStringReplace message, player, extra
      @game.broadcast MessageCreator.genericMessage message

    stripped = MessageCreator._replaceMessageColors message

    # pushbullet for the players!
    if link
      player.pushbulletSend extra.linkTitle, link
    else player.pushbulletSend stripped

    # cache all the things that happen
    @addEventToDb stripped, player, type, extra

    message

  addEventToDb: (message, player, type, extra = {}) ->

    event =
      createdAt: new Date()
      player: player.name
      message: message
      type: type
      extra: extra

    player.recentEvents = [] if not player.recentEvents
    player.recentEvents.unshift event
    player.recentEvents.pop() if player.recentEvents.length > Constants.defaults.player.maxRecentEvents

    @playerEventsDb.insert event, (e, docs) =>
      @game.errorHandler.captureException (new Error "Could not insert event"), event if e

  retrieveEvents: (count = 10, filter = [], newerThan) ->
    defer = Q.defer()

    args = {type: {$not: {$eq: 'towncrier'}}}
    args.player = {$in: filter} if filter.length > 0
    args.createdAt = {$gt: new Date newerThan} if newerThan

    @playerEventsDb.find args, {limit: count, sort: {createdAt: -1}}, (e, docs) ->
      filtered = _.uniq docs, (doc) -> doc.extra?.linkTitle or doc.extra?.partyName or doc.createdAt
      defer.resolve {events: filtered}

    defer.promise

  doYesNo: (event, player, callback) ->
    #player.emit "yesno"
    if chance.bool {likelihood: player.calculateYesPercent()}
      (@broadcastEvent message: event.y, player: player, type: 'miscellaneous') if event.y
      callback true
    else
      (@broadcastEvent message: event.n, player: player, type: 'miscellaneous') if event.n
      callback false

  doItemEquip: (player, item, messageString, type = "item-find") ->
    myItem = _.findWhere player.equipment, {type: item.type}
    score = (player.calc.itemScore item).toFixed 1
    myScore = (player.calc.itemScore myItem).toFixed 1
    realScore = item.score().toFixed 1
    myRealScore = myItem.score().toFixed 1

    player.equip item

    extra =
      item: "<event.item.#{item.itemClass}>#{item.getName()}</event.item.#{item.itemClass}>"

    realScoreDiff = (realScore-myRealScore).toFixed 1
    perceivedScoreDiff = (score-myScore).toFixed 1
    normalizedRealScore = if realScoreDiff > 0 then "+#{realScoreDiff}" else realScoreDiff
    normalizedPerceivedScore = if perceivedScoreDiff > 0 then "+#{perceivedScoreDiff}" else perceivedScoreDiff

    totalString = "#{messageString} [perceived: <event.finditem.perceived>#{myScore} -> #{score} (#{normalizedPerceivedScore})</event.finditem.perceived> | real: <event.finditem.real>#{myRealScore} -> #{realScore} (#{normalizedRealScore})</event.finditem.real>]"
    
    @broadcastEvent {message: totalString, player: player, extra: extra, type: type}

    ##TAG:EVENT_EVENT: findItem | player, item | Emitted when a player finds an item on the ground
    player.emit "event.findItem", player, item

  tryToEquipItem: (event, player, item) ->

    rangeBoost = event.rangeBoost ?= 1

    if (player.canEquip item, rangeBoost) and (chance.bool likelihood: player.calc.itemReplaceChancePercent())
      @doItemEquip player, item, event.remark, event._type
      return true

    else
      multiplier = player.calc.itemSellMultiplier item
      value = Math.floor item.score() * multiplier
      player.gainGold value

      ##TAG:EVENT_PLAYER: sellItem | player, item, value | Emitted when a player sells an item
      player.emit "player.sellItem", player, item, value

module.exports = exports = EventHandler
