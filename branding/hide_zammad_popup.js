(function() {
  var observer = new MutationObserver(function(mutations) {
    mutations.forEach(function(mutation) {
      mutation.addedNodes.forEach(function(node) {
        if (node.nodeType === 1) {
          var text = node.textContent || '';
          if (text.indexOf('improve Zammad') !== -1 || text.indexOf('Help to improve') !== -1) {
            node.style.display = 'none';
            if (node.parentNode) node.parentNode.removeChild(node);
          }
        }
      });
    });
  });
  observer.observe(document.body, { childList: true, subtree: true });
})();
