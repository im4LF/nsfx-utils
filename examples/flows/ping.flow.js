module.exports = {
	def: `
    start(./nodes/Start)
    ping(./nodes/Ping)
    renderer(./nodes/RendererExpress)
    
    start -> ping -> R200 renderer
		ping ERRORS -> R500 renderer`,
	data: {
	}
}