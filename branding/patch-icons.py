import re

logo = open('/opt/zammad/public/assets/images/logo.svg').read()
inner = re.sub(r'<\?xml[^>]+\?>', '', logo)
inner = re.sub(r'<svg[^>]+>', '', inner)
inner = re.sub(r'</svg>', '', inner).strip()

new_full = '<symbol id="icon-full-logo" viewBox="0 0 512 512">\n    <title>Stratechna Desk</title>\n' + inner + '\n</symbol>'
new_logotype = '<symbol id="icon-logotype" viewBox="0 0 512 512">\n    <title>Stratechna Desk</title>\n' + inner + '\n</symbol>'

icons = open('/opt/zammad/public/assets/images/icons.svg').read()
icons = re.sub(r'<symbol id="icon-full-logo"[^>]*>.*?</symbol>', new_full, icons, flags=re.DOTALL)
icons = re.sub(r'<symbol id="icon-logotype"[^>]*>.*?</symbol>', new_logotype, icons, flags=re.DOTALL)

open('/opt/zammad/public/assets/images/icons.svg', 'w').write(icons)
print('icons.svg patched')
