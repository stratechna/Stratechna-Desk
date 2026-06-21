(function() {
  // Substituir texto "Zammad" por "Stratechna Desk" em modais e notificações
  var observer = new MutationObserver(function(mutations) {
    mutations.forEach(function(mutation) {
      mutation.addedNodes.forEach(function(node) {
        if (node.nodeType === 1) {
          var walk = document.createTreeWalker(node, NodeFilter.SHOW_TEXT, null, false);
          var textNode;
          while ((textNode = walk.nextNode())) {
            if (textNode.nodeValue && textNode.nodeValue.indexOf('Zammad') !== -1) {
              textNode.nodeValue = textNode.nodeValue.replace(/Zammad/g, 'Stratechna Desk');
            }
          }
        }
      });
    });
  });
  observer.observe(document.body, { childList: true, subtree: true });

  // Correr também na página actual após carregamento
  document.addEventListener('DOMContentLoaded', function() {
    var walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
    var textNode;
    while ((textNode = walk.nextNode())) {
      if (textNode.nodeValue && textNode.nodeValue.indexOf('Zammad') !== -1) {
        textNode.nodeValue = textNode.nodeValue.replace(/Zammad/g, 'Stratechna Desk');
      }
    }
  });
})();
