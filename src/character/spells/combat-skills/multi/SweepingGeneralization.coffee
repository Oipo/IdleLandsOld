
Spell = require "../../../base/Spell"

class SweepingGeneralization extends Spell
  name: "sweeping generalization"
  @element = SweepingGeneralization::element = Spell::Element.physical
  @tiers = SweepingGeneralization::tiers = [
    {name: "sweeping generalization", spellPower: 1, cost: 350, class: "Generalist", level: 5}
  ]

  calcDamage: ->
    minStat = (@caster.calc.stats ['str', 'dex'])/4
    maxStat = (@caster.calc.stats ['str', 'dex'])/2
    super() + @minMax minStat, maxStat

  determineTargets: ->
    @targetAllEnemies()

  cast: (player) ->
    damage = @calcDamage()
    message = "%casterName cast %spellName and %targetName took %damage HP damage!"
    @doDamageTo player, damage, message

  constructor: (@game, @caster) ->
    super @game, @caster
    @bindings =
      doSpellCast: @cast

module.exports = exports = SweepingGeneralization
