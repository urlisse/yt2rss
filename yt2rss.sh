#!/bin/bash

# Transforme un canal YouTube en fil RSS et télécharge ses épisodes en format MP3.

# @requires yt-dlp 
# @requires jq

# Configuration du site
channel_id=""

site_folder="audio"  # Chemin local vers le dossier MP3s
site_feed="${site_folder}/feed.xml"     # Fichier de sortie RSS
site_url="http://example.com/${site_folder}" # Dossier publique (URL) où les MP3 seront hébergés

#podcast_link="http://example.com"  # Lien vers le site de ton podcast
#podcast_title="Titre du podcast"
#podcast_description="Un podcast généré automatiquement à partir de fichiers MP3."
#podcast_image="http://example.com/image.jpg"  # URL de l'image du podcast
#podcast_date="Mon, 31 Oct 2024 23:00:00 +0000" # Forcer la date de publication en format pubDate
#podcast_author="Nom de l'auteur"
#podcast_owner="${podcast_author}"
#podcast_email="moi@example.com"
#podcast_copyright="(c) 2024 Moi, moi, moi" # Droits d'auteur
#declare -A podcast_categories=(
#  ["Arts"]="Books"
#  ["Society & Culture"]="Documentary,Philosophy"
#) # Jusqu'à 3 catégories -- https://www.podcastinsights.com/itunes-podcast-categories/
#podcast_keywords="book,tv"
#podcast_length=30
podcast_lang="fr" # Langue du podcast

# Fonctions utiles

# Fonction pour convertir la durée en secondes en format HH:MM:SS
format_duration() {
  local seconds=$1
  local hours=$((seconds / 3600))
  local minutes=$(((seconds % 3600) / 60))
  local seconds=$((seconds % 60))
  printf "%02d:%02d:%02d" $hours $minutes $seconds
}

# Fonction pour éviter les caractères interdits dans les fichier XML
escape_xml() {

 local str=$1
 echo $(echo "$str" | sed \
   -e 's/&/\&amp;/g' \
   -e 's/</\&lt;/g' \
   -e 's/>/\&gt;/g' \
   -e 's/\"/\&quot;/g' \
   -e "s/'/\&apos;/g")
}

# Chargement de la configuration
if [ -z "$1" ]; then
	echo "usage: $(basename "$0") <configuration> [<action>]"
  echo
  echo "<configuration>   charge le fichier de configuration <configuration>.config"
  echo "<action>"
  echo "    fetch        télécharge les fichiers manquants à partir de YouTube"
	exit 1;
fi

site=$1
site=$(basename "${site%.*}")

echo "Chargement de la configuration de '${site}'."
source "${site}.config"

# Télécharger la version mp3 du site
channel_url="https://www.youtube.com/channel/${channel_id}"

filename_format="%(upload_date)s-%(id)s.%(ext)s" # Format du nom de fichier des contenus téléchargés
filename_channel="${site_folder}/NA-${channel_id}.info.json"  # Trouver le fichier JSON correspondant
filename_archive="${site_folder}.txt" # Mémoire des fichiers téléchargés

case "$2" in
  fetch)
  echo "Récupération des fichiers manquants..."
  yt-dlp -x --audio-format mp3 --add-metadata --embed-thumbnail --write-info-json --download-archive "${filename_archive}" -o "${site_folder}/${filename_format}" "${channel_url}"
  ;;
esac

echo "Regénération du flux $filename_channel"

# Assigner la liste des fichiers de métadonnées à un tableau, dans l'ordre chronologique inverse
IFS=$'\n' read -r -d '' -a items < <(find "${site_folder}" -maxdepth 1 -type f -name "*.json" | grep -E '/[0-9]{8}-.*\info.json$' | sort -r)

if [ -n "${podcast_length}" ]; then
 items=("${items[@]:0:$podcast_length}") 
fi

new_array=("${my_array[@]:0:$n}")

if [ -z "${podcast_link}" ]; then
  podcast_link=$(jq -r '.uploader_url // empty' "$filename_channel")
fi
if [ -z "${podcast_title}" ]; then
  podcast_title=$(jq -r '.channel // empty' "$filename_channel")
fi
if [ -z "${podcast_description}" ]; then
  podcast_description=$(jq -r '.description // empty' "$filename_channel")
fi
if [ -z "${podcast_image}" ]; then
  podcast_image=$(jq -r '.thumbnails[0].url // empty' "$filename_channel")
fi
if [ -z "${podcast_author}" ]; then
  podcast_author=$(jq -r '.uploader // empty' "$filename_channel")
fi
if [ -z "${podcast_keywords}" ]; then
  podcast_keywords=$(jq -r '.tags[] // empty' "$filename_channel")
  podcast_keywords=$(echo -e "${podcast_keywords}" | tr '\n' ',' | sed 's/,$//')
fi

if [ -z "${podcast_date}" ]; then
  # Récupérer les métadonnées plus récent item publié
  item_json="${items[0]}"
  timestamp=$(jq -r '.timestamp' "$item_json")
  if [ -n "$timestamp" ]; then
    podcast_date="$(date -R -u -d @$timestamp)"
  else
    podcast_date=$(jq -r '.epoch // empty' "$filename_channel")
    podcast_date=$(date -R -u -d @$podcast_date)
  fi
fi

build_date=$(date -R -u)

# Générer l'en-tête du flux RSS
cat <<EOL > $site_feed
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel>
  <title>$(escape_xml "$podcast_title")</title>
  <link>$(escape_xml "$podcast_link")</link>
  <description><![CDATA[$podcast_description]]></description>
  <language>$podcast_lang</language>
  <pubDate>$podcast_date</pubDate>
  <lastBuildDate>$build_date</lastBuildDate>
  <itunes:author>$(escape_xml "$podcast_author")</itunes:author>
  <itunes:image href="$(escape_xml "$podcast_image")" />
EOL

for supercat in "${!podcast_categories[@]}"; do
	# Afficher la super-catégorie
  echo "  <itunes:category text=\"$(escape_xml $supercat)\">" >> $site_feed
	
	# Diviser les sous-catégories par la virgule et les afficher
	IFS=',' read -ra subcategories <<< "${podcast_categories[$supercat]}"
	for subcat in "${subcategories[@]}"; do
    echo "    <itunes:category text=\"$(escape_xml $subcat)\"/>" >> $site_feed
	done

	# Fermer la balise de la super-catégorie
	echo "  </itunes:category>" >> $site_feed
done

if [ -n "${podcast_keywords}" ]; then
  echo "  <itunes:keywords>$(escape_xml $podcast_keywords)</itunes:keywords>" >> $site_feed
fi

if [ -n "${podcast_email}" ]; then
  cat <<EOL > $site_feed
  <itunes:owner>
    <itunes:name>$(escape_xml "$podcast_owner")</itunes:name>
    <itunes:email>$(escape_xml "$podcast_email")</itunes:email>
  </itunes:owner>
EOL
fi

if [ -n "${copyright}" ]; then
  echo "  <copyright>$podcast_copyright</copyright>" >> $site_feed
fi

# Boucle à travers les fichiers MP3 et extraire les métadonnées pour créer les items RSS
for item_json in "${items[@]}"; do
    file_name=$(basename "$file_audio")
    file_url="${site_url}/${file_name}"
    file_audio="${item_json%.info.json}.mp3"  # Trouver le fichier JSON correspondant
    if [[ -f "$file_audio" ]]; then
      file_size=$(stat -c%s "$file_audio")
    fi

    echo "Insertion de l'item $item_json ..."

    # Extraire les métadonnées du fichier JSON
    guid=$(jq -r '.id' "$item_json")
    guid="yt:video:${guid}"
    title=$(jq -r '.title' "$item_json")
    artist=$(jq -r '.artist // .uploader' "$item_json")
    description=$(jq -r '.description' "$item_json")
    duration=$(jq -r '.duration' "$item_json")
    duration=$(format_duration $duration)  # Convertir la durée en HH:MM:SS
    youtube_url=$(jq -r '.webpage_url' "$item_json")
    image=$(jq -r '.thumbnail // empty' "$item_json")
    if [ -z "$image" ]; then
      image="$podcast_image"
    fi
    timestamp=$(jq -r '.timestamp' "$item_json")
    if [ -n "$timestamp" ]; then
      pub_date="$(date -R -u -d @$timestamp)"
    else
      pub_date=$podcast_date
    fi
    itype=$(jq -r '.series // "episodic"' "$item_json")  # S'il y a une série, sinon type "episodic"
    episode=$(jq -r '.episode_number // empty' "$item_json")  # Si le numéro d'épisode est présent
    season=$(jq -r '.season_number // empty' "$item_json")  # Si le numéro de saison est présent
    # Ajouter l'item RSS
    cat <<EOL >> $site_feed
  <item>
    <guid isPermaLink="false">$(escape_xml "$guid")</guid>
    <title>$(escape_xml "$title")</title>
    <description><![CDATA[$description

    <a href="$(escape_xml "$youtube_url")">Écouter la vidéo sur YouTube</a>.]]></description>
    <enclosure url="$(escape_xml "$file_url")" length="$(escape_xml "$file_size")" type="audio/mpeg" />
    <link>$(escape_xml "$youtube_url")</link>
    <source url="$(escape_xml "$youtube_url")">$(escape_xml "$title") sur YouTube</source>
    <pubDate>$(escape_xml "$pub_date")</pubDate>
    <itunes:image>$(escape_xml "$image")</itunes:image>
    <itunes:duration>$(escape_xml "$duration")</itunes:duration>
EOL
  if [[ -n "$season" ]]; then
    cat <<EOL >> $site_feed
    <itunes:season>$(escape_xml "$season")</itunes:season>
EOL
  fi

  if [[ -n "$episode" ]]; then
    cat <<EOL >> $site_feed
    <itunes:episode>$(escape_xml "$episode")</itunes:episode>
    <itunes:type>$(escape_xml "$itype")</itunes:type>
EOL
  fi

    cat <<EOL >> $site_feed
  </item>
EOL
done

# Ajouter le pied de page du flux RSS
cat <<EOL >> $site_feed
</channel>
</rss>
EOL

echo "Fichier RSS généré : $site_feed"

