module.exports = (args, env) => ({
	out_: 1,
	invalid_: 1,
	errors_: 1,
	_in(message, done) {
		message.url = {
			raw: message.rq.url,
			params: message.rq.params,
			query: message.query,
		}
		
		this.send('out', message, done)
	}
})