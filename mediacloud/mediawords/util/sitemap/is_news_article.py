import re
from urllib.parse import urlparse


def _has_number_in_string(string: str) -> bool:
    return any(char.isdigit() for char in string)


def url_points_to_news_article(url: str) -> bool:
    """
    Return True if URL looks like it's pointing to a news article.

    Configured to work with sitemap-derived Colombian news sources only.

    :param url: URL to test.
    :return: True if URL looks like it's pointing to a news article.
    """
    uri = urlparse(url)
    if uri.path == '/' or not uri.path:
        return False

    if '://laorejaroja.com' in url:

        if '/tag/' in url:
            return False

        # e.g. "https://www.laorejaroja.com/2016-no-te-soportabamos-un-dia-mas/samboni/"
        if url.count('/') >= 5:
            return False

    elif '//eltiempo.com' in url:

        # e.g. "http://eltiempo.com/noticias/pacifico-colombiano"
        if url.count('/') == 4:
            if '/noticias/' in url:
                return False

    elif '//elespectador.com/' in url:

        if 'articulo' in url:
            return True

        if '/noticias/' in url:
            return True

        if '/content/' in url:
            return True

        if '-image-' in url:
            return False

        if '-imagen-' in url:
            return False

        if not _has_number_in_string(url):
            return False

    elif '//semana.com' in url or '//especiales.semana.com' in url:

        if url.endswith('.html') or url.endswith('/'):
            return False

    elif '//colombia.com' in url:
        if url.endswith('/'):
            return False

        if url.count('/') == 4:
            if '/tv/' in url or '/radio/' in url or '/cine/' in url:
                return False

    elif '//caracoltv.com/' in url:
        # e.g. "http://caracoltv.com/vozpopuliteve"
        if url.count('/') == 3:
            return False

    elif '//elpais.com.co' in url:
        if not url.endswith('.html'):
            return False

    elif '//elcolombiano.com' in url:

        if not re.search(r'.+?-\w\w\d\d\d\d\d\d\d\d$', url):
            return False

    elif '//lasillavacia.com' in url:

        if '/users/' in url or '/user/' in url:
            return False

        if '/content/' in url:
            return True

        if re.search(r'-\d+$', url):
            return True

        # e.g. "http://lasillavacia.com/silla-llena/red-verde/historia/colombia-no-esta-lista-para-aumentar-la-exploracion-de-hidrocarburos"
        if url.count('/') >= 5:
            return True

        # e.g. "http://lasillavacia.com/quienesquien/perfilquien/alejandro-char-chaljub"
        if '/quienesquien/' in url and not url.endswith('/'):
            return True

    elif '//rcnradio.com' in url:

        if url.endswith('/'):
            return False

        # e.g. "http://rcnradio.com/bogota"
        if url.count('/') <= 3:
            return False

    elif '//pulzo.com' in url:

        # e.g. "http://pulzo.com/tecnologia"
        if url.count('/') <= 3:
            return False

    elif '//dinero.com' in url:

        if not re.search(r'/\d+$', url):
            return True

    elif '//elheraldo.co' in url:
        # Only category pages in sitemap
        return False

    elif '//eluniversal.com.co' in url:
        if not re.search(r'.+?-\w\w\d+?$', url):
            return False

    elif '//diariodelcauca.com.co' in url or '//hsbnoticias.com' in url or '//autocosmos.' in url:
        # Only category pages in sitemap
        return False

    elif '//publimetro.co' in url:
        if not url.endswith('.html'):
            return False

    elif '//lanacion.com.co' in url:
        if not re.search(r'/\d\d\d\d/\d\d/\d\d/', url):
            return False

    elif '//todaycolombia.com' in url:
        if re.search(r'-\d+x\d+', url):
            return False

        if not re.search(r'todaycolombia\.com/.{20,}?/', url):
            return False

    elif '//portafolio.co' in url:
        if not re.search(r'-\d+?$', url):
            return False

    elif '//canalrcn.com' in url:
        if url.endswith('/'):
            return False

    elif '//vanguardia.com' in url:
        if not re.search(r'.+?-\w\w\d+?$', url):
            return False

    elif '//caqueta.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//diariodelsur.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//contagioradio.com' in url:
        if '/tag/' in url:
            return False
        if '/categoria/' in url:
            return False

    elif '//hsbnoticias.com' in url:
        # Everything looks like cruft
        return False

    elif '//razonpublica.com' in url:
        if '/component/' in url:
            return False
        if '/tag/' in url:
            return False
        # e.g. "http://razonpublica.com/index.php/econom-y-sociedad-temas-29/11089-la-educaci%C3%B3n.html"
        if url.count('/') not in [5, 6]:
            return False

    elif '//actualidadpanamericana.com' in url:
        if '/tag/' in url:
            return False
        if '-jpg' in url:
            return False
        if not re.search(r'actualidadpanamericana\.com/.{20,}?/', url):
            return False

    elif '//laotracara.co' in url:
        if '/tag/' in url:
            return False
        if url.count('/') <= 4:
            return False

    elif '//elpilon.com.co' in url:
        if '/tag/' in url:
            return False
        if '/foto' in url:
            return False

    elif '//ibague.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//fedesarrollo.org.co' in url:
        if '/content/' not in url and '/publicaciones/' not in url and '/propuestas_de_gobierno/' not in url:
            return False

    elif '//lanotaeconomica.com.co' in url:
        if '/attachment/' in url:
            return False
        if '/tag/' in url:
            return False
        if '?attachment_id=' in url:
            return False
        if not url.endswith('.html'):
            return False

    elif '//revistadiners.com.co' in url:
        if not re.search(r'/\d+?[-_].+?/$', url):
            return False

    elif '//elmundo.com' in url:
        if '/noticia/' not in url:
            return False

    elif '//qhubo.com' in url:
        if '/etiqueta/' in url:
            return False
        # e.g. "http://qhubo.com/fue-placer-trabajar-tom-cruise/mauricio-mejia/"
        if url.count('/') == 5:
            return False

    elif '//teleantioquia.co' in url:
        # Everything looks like cruft
        return False

    elif '//bogotafreeplanet.com' in url:
        if '/bogota/' not in url:
            return False

    elif '//thecitypaperbogota.com' in url:
        if '/date/' in url:
            return False
        if '/author/' in url:
            return False
        if not re.search(r'/\d+$', url):
            return False

    elif '//opanoticias.com' in url:
        if not re.search(r'/\d+$', url):
            return False

    elif '//elinformador.com.co' in url:
        if url.count('/') < 6:
            return False
        if not re.search(r'/\d+-[^/]+?$', url):
            return False

    elif '//occidente.co' in url:
        if '/attachment/' in url:
            return False
        if '/tag/' in url:
            return False
        if '/author/' in url:
            return False
        if url.count('/') <= 4:
            return False

    elif '//pacifista.tv' in url:
        if '/tag/' in url:
            return False
        # e.g. "http://pacifista.tv/notas/13-estrategias-raras-de-los-politicos-colombianos-para-llamar-la-atencion/2056926-2/"
        if url.count('/') > 5:
            return False

        if re.search(r'[-_]\d+x\d+', url):
            return False

    elif '//girardot.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//boyaca.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//huila.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//gatopardo.com' in url:
        # e.g. "http://gatopardo.com/abel-membrillo/"
        if url.count('/') <= 4:
            return False

    elif '//thebogotapost.com' in url:
        if '/event/' in url:
            return True
        if '/tag/' in url:
            return False
        # e.g. "http://thebogotapost.com/zipaquira-cycled-like-never-before/9641/"
        if not re.search(r'/\d+/$', url):
            return False

    elif '//llano.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//casanare.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//cali.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//chiquinquira.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//ladorada.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//cauca.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//pasto.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//cucuta.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//putumayo.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//barrancabermeja.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//palmira.extra.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//elperiodicodeportivo.com.co' in url:
        # Everything looks like cruft
        return False

    elif '//investincolombia.com.co/' in url:
        if '/news/' not in url:
            return False

    elif '//elexpediente.co' in url:
        if '/tag/' in url:
            return False

    elif '//infobae.com' in url:
        if not re.search(r'/\d\d\d\d/\d\d/\d\d/', url):
            return False

    elif '//lapiragua.co' in url:
        # e.g. "http://lapiragua.co/suicidio-valentia-o-coraje/salud/"
        if url.count('/') < 5:
            return False

    elif '//rptnoticias.com' in url:
        if not re.search(r'/\d\d\d\d/\d\d/\d\d/', url):
            return False

    elif '//revistametro.co' in url:
        if not re.search(r'/\d\d\d\d/\d\d/\d\d/', url):
            return False

    elif '//minuto30.com' in url:
        if '/author/' in url:
            return False
        if '/date/' in url:
            return False
        # e.g. "http://thebogotapost.com/zipaquira-cycled-like-never-before/9641/"
        if not re.search(r'/\d+/$', url):
            return False

    return True
