import deepmerge from 'deepmerge'
import path from 'path'
import stream from 'stream'
import pino from 'pino'
import { parse } from './parser.mjs'

const logger = pino({
	transport: {
		target: 'pino-pretty',
	},
})

async function build(def, props, env) {

	env = Object.assign({ logger }, env)
	let def_parsed = parse(def)
	env.logger.debug({ def_parsed, nodesdir: env.nodesdir }, 'build')

	let processes = {}
	let components = {}
	let errors = []

	for (const [name, item] of Object.entries(def_parsed.processes)) {
		let component_path = item.component
		let component_args = props[name] || item.metadata || {}
		if (!(item.component in components)) {
			components[ item.component ] = await get_component(component_path, component_args, env)
		}

		processes[name] = await create_process(name, components[item.component], component_args, env)
	}


	let uniq = {}
	for (const item of def_parsed.connections) {
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
	}

	if (errors.length) 
		throw new Error(errors)
	
	return processes
}

async function get_component(nodepath, args, env) {
	
	if (nodepath.startsWith('./'))
		nodepath = path.resolve(env.nodesdir, nodepath)

	let node = await import(nodepath + '.node.js')
	if ('default' in node) {
		node = node.default
	}

	env.logger.debug({ nodepath, node }, 'get_component')

	if (typeof node === 'function') 
		return node(args, env)
	else
		return node
}

async function create_process(name, component, args, env, done) {
	done = done || function () {}
	let config = {}
	let base = component.base || []
	base.forEach(x => {
		let buf = x
		if (typeof x === 'string') 
			buf = get_component(x, args, env)
		
		config = deepmerge(config, buf)
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
			highWaterMark: 128,
			objectMode: true,
			write: (message, _, done) => res[ '_' + port ](message, done)
		})
	})

	let outports = Object.keys(config).filter(x => x.endsWith('_')).map(x => x.substr(0, x.length - 1))
	outports.forEach(port => {

		res[port] = new stream.Readable({
			highWaterMark: 128,
			objectMode: true,
			read() {}
		})
	})

	env.logger.debug({ process: res.name, config, res }, 'create_process')

	await res.init(done)
	return res
}

export {
	build,
	create_process,
	parse,
}