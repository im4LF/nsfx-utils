'use strict'

const deepmerge = require('deepmerge')
const path = require('path')
const stream = require('stream')
const logger = require('pino')({ prettyPrint: true })
const parser = require('./parser')

function build(def, props, env, done) {

    env = Object.assign({ logger }, env)
    let def_parsed = parser.parse(def)
    env.logger.debug({ def_parsed, dir: process.env })

    let processes = {}
    let components = {}
    let names = Object.keys(def_parsed.processes)
    let errors = []

    const init_connections = () => {
        
        let uniq = {}
        def_parsed.connections.forEach(item => {

            let out_port = processes[item.src.process][item.src.port]
            let in_port = processes[item.tgt.process][item.tgt.port]

            if (!out_port) {
                errors.push({ code: 'PORT_NOT_DEFINED', message: `Node ${item.src.process} port ${item.src.port}`, item })
                return
            }
            if (!in_port) {
                errors.push({ code: 'PORT_NOT_DEFINED', message: `Node ${item.tgt.process} port ${item.tgt.port}`, item })
                return
            }

            let key = [ item.src.process, item.src.port, item.tgt.port, item.tgt.process ].join('--')
            if (key in uniq) {
                logger.warn({ item }, 'Already connected')
                return
            }

            out_port.pipe(in_port)
            uniq[key] = 1
        })

        if (errors.length) 
            done(errors)
        else
            done(null, processes)
    }

    const init_process = () => {

        let name = names.shift()
        if (!name) return init_connections()

        let item = def_parsed.processes[name]
        let component_path = item.component
        let component_args = props[name] || item.metadata || {}
        if (!(item.component in components)) {
            
            components[ item.component ] = get_component(component_path, component_args, env)
        }

        create_process(name, components[item.component], component_args, env, (err, res) => {

            if (err) return done(err)

            processes[name] = res
            init_process()
        })
    }

    init_process()
}

function get_component(nodepath, args, env) {
    
    if (nodepath.startsWith('./'))
        nodepath = path.resolve(env.nodesdir, nodepath)

    let node = require(nodepath + '.node.js')
    if (typeof node === 'function') 
        return node(args, env)
    else
        return node
}

function create_process(name, component, args, env, done) {

    let config = {}
    let base = component.base || []
    base.forEach(x => {
        config = deepmerge(config, x)
    })
    config = deepmerge(config, component)

    let res = Object.create({
        name,
        props: {},
        init: config.init || function init(done) { done(null, this) },
        logger: env.logger,
        send(port, message, done) {

            this[port].push(message)
            if (typeof done === 'function') done()
        }
    })

    if (config.props instanceof Array) {
        config.props.forEach(name => res.props[name] = args[name])
    }
    else if (typeof config.props === 'object') {
        let errors = []
        Object.keys(config.props).forEach(prop => {

            res.props[prop] = prop in args ? args[prop] : config.props[prop].default
            if (config.props[prop].required && res.props[prop] === undefined)
                errors.push({ code: 'REQUIRED_PROP', message: `Process ${name} have required ${prop}` })
        })

        if (errors.length) return done(errors)
    }

    let inports = Object.keys(config).filter(x => x.startsWith('_') && typeof config[x] === 'function').map(x => x.substr(1))
    inports.forEach(port => {

        res['_' + port] = config['_' + port]
        res[port] = new stream.Writable({
            objectMode: true,
            write: (message, _, done) => res[ '_' + port ](message, done)
        })
    })

    let outports = Object.keys(config).filter(x => x.endsWith('_')).map(x => x.substr(0, x.length - 1))
    outports.forEach(port => {

        res[port] = new stream.Readable({
            objectMode: true,
            read() {}
        })
    })

    env.logger.debug({ name, config, res }, 'create_process')

    res.init(done)
}

module.exports = {
    build,
    create_process
}