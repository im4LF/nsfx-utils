module.exports = {
	def: `
    start(./nodes/Start)
    hello(./nodes/Hello)
    renderer(./nodes/RendererExpress)
    
    start -> hello -> R200 renderer`,
	data: {
	}
}