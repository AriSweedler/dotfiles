local M = {
	"afewyards/codereview.nvim",
	dependencies = { "nvim-lua/plenary.nvim" },
	cmd = {
		"CodeReview",
		"CodeReviewAI",
		"CodeReviewAIFile",
		"CodeReviewStart",
		"CodeReviewSubmit",
		"CodeReviewApprove",
		"CodeReviewOpen",
		"CodeReviewPipeline",
		"CodeReviewComments",
		"CodeReviewFiles",
	},
	opts = {},
}

return M
