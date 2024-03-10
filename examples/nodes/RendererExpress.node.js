module.exports = (args, env) => ({
	out_: 1,
	errors_: 1,
	_r200(message, done) {
		message.rs.send(message.data)
		done()
	},
	_r400(message, done) {
		message.rs
			.status(400)
			.json(message.data)
		done()
	},
	_r404(message, done) {
		message.rs
			.status(404)
			.json(message.data)
		done()
	},
	_r500(message, done) {
		message.rs
			.status(500)
			.json(message.error)
		done()
	},
})