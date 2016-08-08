Config = require './Config'
Horizon = require '@horizon/client/dist/horizon'
localStorage = new (require 'node-localstorage').LocalStorage(Config.local_storage)

class Vault
  constructor : (app, host, watcherFP, clientFP, cb) ->
    @app = app
    authType = @getToken()
    secure = Config.secure
    @hz = Horizon({host, authType, secure})

    @hz.connect()
    @users = @hz 'users'
    @settings = @hz 'settings'
    @events = @hz 'events'

    @hz.onReady () =>
      token = JSON.parse(@hz.utensils.tokenStorage._storage._storage.get('horizon-jwt')).horizon
      localStorage.setItem 'horizon-jwt', token
      await @hz.currentUser().fetch().subscribe defer me
      unless me.data
        me.data =
          key: watcherFP
        @users.replace me
      console.log 'Me:', me
      cb and cb this

    @hz.onDisconnected (e) =>
      unless @retried
        @retried = true
        localStorage.removeItem 'horizon-jwt'
        @constructor app, host, watcherFP, clientFP, cb

  getToken : () ->
    jwt = localStorage.getItem 'horizon-jwt'
    if jwt
      { token: jwt, storeLocally: false }
    else
      'anonymous'

  save : (col, object, cb) ->
    console.log "Saving into #{col}"
    console.log 'SAVING', object
    this[col]?.store object
    cb and cb true

  replace : (col, object, cb) ->
    console.log "Replacing into #{col}"
    this[col]?.replace object
    cb and cb true

  get : (col, query, cb) ->
    this[col]?.find(query).fetch().subscribe (items) ->
      cb and cb items

  watch : (col, query, cb) ->
    this[col]?.find(query).watch().subscribe (items) ->
      cb and cb items

  remove : (col, ids, cb) ->
    console.log "Removing from #{col}"
    res = this[col].removeAll(ids)
    cb and cb res

module.exports = Vault
