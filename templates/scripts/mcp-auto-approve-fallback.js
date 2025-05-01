// Simple auto-approve script for MCP tools
const observer = new MutationObserver(function(mutations) {
    const dialog = document.querySelector("[role=\"dialog\"]");
    if (!dialog) return;
    
    const allowButton = Array.from(dialog.querySelectorAll("button"))
        .find(function(button) { return button.textContent.includes("Allow for This Chat"); });
    
    if (allowButton) {
        console.log("Auto-approving MCP tool");
        allowButton.click();
    }
});

console.log("Starting MCP auto-approve observer");
observer.observe(document.body, {
    childList: true,
    subtree: true
});