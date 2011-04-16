#!/usr/bin/perl -w

## Script quotidien de recrutement de corpus pour corpus-2010

use strict;
use Decoupage;

use LWP::UserAgent;
use LWP::Simple;
use URI::URL;
#use HTML::Entities; #Problème avec ce module : il utilise la fonction 'chr' qui renvoie des caractères non utf-8 pour les car dont le code est entre 128 et 255
use Encode;
use File::Spec;
use Time::HiRes;

# Liste des langues cibles
#my @lang = qw(allemand anglais-RU anglais-USA chinois coreen francais golfe japonais maghreb-ar orient persan);

my @lang = qw(francais anglais espagnol allemand arabe russe japonais);
#my @lang = qw(russe);

my $current_dir;
if(@ARGV == 1) {$current_dir = $ARGV[0];}
else{$current_dir = File::Spec->curdir();}


foreach my $lang (@lang){
  my $lang_dir = File::Spec->catfile($current_dir, $lang);
  my $lang_dir_url_file = File::Spec->catfile($lang_dir, "url.txt");
  my $lang_dir_keywords_file = File::Spec->catfile($lang_dir, "keywords.txt");
  
  # Pour chaque langue il doit exister un répertoire ayant le code langue pour nom
  # Chaque répertoire doit comporter un fichier url.txt avec la liste des url et un fichier keywords.txt avec les mots clés
  if(-d $lang_dir && -e $lang_dir_url_file && -e $lang_dir_keywords_file){
    open(URL, "<$lang_dir_url_file") or print STDERR "$!";
    
    
    while(<URL>){
      chomp $_;
      my $url = $_;
      
      # Un répertoire par site web
      my $short_url = $url;
      $short_url =~ s/http:\/\/([^\/]+)\/.*/$1/;
      print STDERR "$short_url\n\n";
      
      # création du répertoire du site web
      my $url_dir = File::Spec->catfile($lang_dir, $short_url);
      unless(-d $url_dir){ mkdir $url_dir; }
      
      # création du répertoire portant la date du jour
      # (annéemoisjour)
      my $url_dir_time = File::Spec->catfile($url_dir, _getDate());
      unless(-d $url_dir_time){ mkdir $url_dir_time; }
      
      my @keywords = undef; #tableau de mots clés pour langue/culture en cours de traitement
      &getKeyWords(\@keywords, $lang_dir_keywords_file);
      my @links = undef; #tableau de liens contenus dans url de départ
      &crawl($url, \@links); 

      #Pour chaque page pointée par la page d'accueil
      #Si un mot clé est trouvé, on la télécharge et convertit en texte
      foreach my $link (@links){
	my @foundKeywords = &matchKeyWord($link, $short_url, \@keywords);
	if(scalar(@foundKeywords) != 0){
	  print "Trouvé @foundKeywords dans $link\n";
	  &getFile($url_dir_time, $link, $short_url, \@foundKeywords);
	}
	else{
	  print STDERR "No keywords found for $link\n";
	}
      }
    }
    close URL;
  }
}
#-------------------------------------------------#
# Fin main					  #
#-------------------------------------------------#

## getKeyWords
## Arguments : ref tableau de mots clés, fichier mots clés
sub getKeyWords{
  my $refTab = shift;
  my $file = shift;
  
  open(KEYWORDS, "<$file") or die "$!";
  
  while(<KEYWORDS>){
    chomp $_;
    push(@$refTab, $_);
  }
  
  close KEYWORDS;
}

## crawl
## Arguments : url, ref tableau liens (liens internes, extension html)
sub crawl{
  my $domain = shift;
  my $refResult = shift;
  my $content;
  my %tmp;
  
  #Telechargement contenu HTML
  my $ua = LWP::UserAgent->new();
  my $response = $ua->get($domain);
  if($response->is_success){
    $content = $response->content;
  }
  else{
    print STDERR "Erreur téléchargement fichier : ".$response->status_line." - ".$domain;
    return 0;
  }
  
  #Recherche des liens hypertextes contenus dans la page
  foreach my $url ($content =~/href=["']([^"']+)["']/gi){
    my $urlObj = URI::URL->new($url, $domain);
    $url = $urlObj->abs; 
    #On ne retient que les liens pointant vers le nom de domaine recherché
    if($url =~ /$domain/){
      $tmp{$url}++;
    }
    $urlObj = undef;
  }
  push(@$refResult, keys(%tmp));	
  $ua = undef;
}


## matchKeyWord
## Arguments : URL (string), nom journal (string), ref tableau de mots clés
## Retour  : liste des mots clés trouvés
sub matchKeyWord{
  my $url = shift;
  my $journal = shift;
  my $refKeywordTab = shift;
  
  my @foundKeywords;
  my $content = "";
  
  
  #Telechargement contenu HTML
  #Et conversion en utf-8
  getstore($url, "tmp_corpus.html") || return @foundKeywords;
  init($journal, "tmp_corpus.html") || return @foundKeywords;
  my $encodage = getEncodage();
  return @foundKeywords unless defined($encodage);
  print STDERR "$encodage\n";
  my $contenu = getContenu("txt");
  Encode::from_to($contenu, $encodage, "UTF-8");
  
  print STDERR "$contenu\n";

  foreach my $keyword (@$refKeywordTab){
#    if($contenu =~ m/(\p{isSpace}|\p{isPunct})$keyword(\p{isSpace}|\p{isPunct})/){
    if($contenu =~ m/$keyword/i){
      push(@foundKeywords, $keyword);
    }
  }
  return @foundKeywords;
}

  
## getFile
## Télécharge, normalise et encode en UTF8 une page web (utilisation de HTML2TxtObj.pm)
## Arguments : répertoire de sortie, URL de la page, nom du journal, ref de la liste de mots clés trouvés dans la page
sub getFile{
  my $url_dir_time = shift;	#Le répertoire de sortie
  my $url = shift;		#URL de la page à collecter
  my $journal = shift;	#Nom du journal (pour Decoupage)
  my $refFoundKeywords = shift;		#Réf de la liste des mots clés trouvés dans la page
  
  my $date = _getDate();
  my $hiResTime = _getHiResTime();
  
  # génération de 4 fichiers par url : 
  # - log
  # - html
  # - html-decoupe
  # - xml utf8
  my $log_file = File::Spec->catfile($url_dir_time, $date."-".$hiResTime.".log");
  my $html_file = File::Spec->catfile($url_dir_time, $date."-".$hiResTime.".html");
  my $html_decoup_file = File::Spec->catfile($url_dir_time, $date."-".$hiResTime."-decoup.html");
  my $xml_file = File::Spec->catfile($url_dir_time, $date."-".$hiResTime.".xml");
  open(LOG,">$log_file") or die "$!";
  
  my $localtime = localtime();
  print LOG "$localtime\n";
  
  getstore($url, $html_file) || print LOG "Download of $url failed\n";
  if(init($journal, $html_file)){
    my $extended = _getExtendedTime();
    print LOG "$extended --- Downloaded HTML page of $url, stored into $html_file\n";
    
    my $encodage = getEncodage();
    print LOG "$extended --- $encodage is charset of $url\n";
    return "" unless defined($encodage);
    
    decoupageHTML($journal, $html_file, $html_decoup_file, $encodage, $extended, \*LOG);
    decoupageXML($journal, $html_file, $xml_file, $encodage, $extended, $refFoundKeywords, \*LOG);
    
    #Ecriture des mots clés trouvés dans le fichier log
    print LOG "Keywords found -- ";
    print LOG join(":",@$refFoundKeywords);
  }
  else{
    print LOG "Processing of $url failed\n";
    print "\n";
  }
  close LOG;
}

#decoupageHTML : decoupe le contenu de l'article contenu dans la page web
sub decoupageHTML{
  my ($journal, $html_file, $html_decoup_file, $encodage, $extended, $log) = @_;
  init($journal, $html_file);
  my $contenu_html = getContenu("html");
  my $date_html = getDate("html");
  my $titre_html = getTitre("html");
  open(HTML_DECOUP,">$html_decoup_file") or die "$!";
  
  print HTML_DECOUP "<!-- Encodage -->\n$encodage\n\n";
  print HTML_DECOUP "<!-- Titre -->\n$titre_html\n\n";
  print HTML_DECOUP "<!-- Date -->\n$date_html\n\n";
  print HTML_DECOUP "<!-- Contenu -->\n$contenu_html";
  
  close HTML_DECOUP;
  
  print $log "$extended --- Transformed $html_file into html-decoup, stored into $html_decoup_file\n";
} 

## decoupageXML : génère le fichier XML en utf8 (mots clés, titre, date, contenu)
sub decoupageXML{
  my ($journal, $html_file, $xml_file, $encodage, $extended, $refFoundKeywords, $log) = @_;
  init($journal, $html_file);
  my $contenu = getContenu("txt");
  my $date = getDate("txt");
  my $titre = getTitre("txt");
  Encode::from_to($contenu, $encodage, "UTF-8");
  $contenu = _decode_entities($contenu);
  Encode::from_to($date, $encodage, "UTF-8");
  $date = _decode_entities($date);
  Encode::from_to($titre, $encodage, "UTF-8");
  $titre = _decode_entities($titre);
  
  open(XML, ">$xml_file") or die "$!";
  print XML "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  print XML "<document>\n";
  print XML "<original_charset>$encodage</original_charset>\n";
  print XML "<found_keywords>";
  print XML join(":",@$refFoundKeywords);
  print XML "</found_keywords>\n";
  print XML "<title>$titre</title>\n";
  print XML "<date>$date</date>\n";
  print XML "<content>$contenu</content>\n";
  print XML "</document>\n";
  close XML;
  
  print LOG "$extended --- Transformed $html_file into utf8 xml, stored into $xml_file\n";
}
  
## _getDate
## Retourne une date simplifiée au format
## annéemoisjour
## (ex : 20080112)
sub _getDate{
  my @monthNumber = qw ( 01 02 03 04 05 06 07 08 09 10 11 12 );
  
  my $year = (localtime)[5]+1900;
  my $month = $monthNumber[(localtime)[4]];
  my $day = (localtime)[3];
  $day = "0".$day if($day !~ /[0-9]{2}/);
  my $time = $year.$month.$day;
  return $time;
}

## _getExtendedTime
## Retourne la date et l'heure au format
## annéemoisjour : heure : minute : seconde
## (ex : 20080126:23:37:50)
sub _getExtendedTime{
  my @monthNumber = qw ( 01 02 03 04 05 06 07 08 09 10 11 12 );
  my $year = (localtime)[5]+1900;
  my $month = $monthNumber[(localtime)[4]];
  my $day = (localtime)[3];
  
  my $extendedTime = $year.$month.$day.":".(localtime)[2].":".(localtime)[1].":".(localtime)[0];
  return $extendedTime;
}

## _getHiResTime
## Utilisation du module HiRes
## Informations plus précises que time()
## (permet d'avoir de noms de fichiers différents à coup sur)
sub _getHiResTime
  {
    my $hiResTime = Time::HiRes::time();
    return $hiResTime;
  }
  
## _decode_entities
## Conversion maison des entités HTML (problème avec HTML::Entities voir plus haut)
sub _decode_entities{
  my $string = shift;
my %entity2char = ("&quot;" => "\"",
		   "&apos;" => "'",
		   "&amp;" => "&",
		   "&lt;" => "<",
		   "&gt;" => ">",
		   "&nbsp;" => " ",
		   "&Agrave;" => "À",
		   "&Aacute;" => "Á",
		   "&Acirc;" => "Â",
		   "&Atilde;" => "Ã",
		   "&Auml;" => "Ä", 
		   "&Aring;" => "Å", 
		   "&AElig;" => "Æ",
		   "&Ccedil;" => "Ç",
		   "&Egrave;" => "È",
		   "&Eacute;" => "É",
		   "&Ecirc;" => "Ê",
		   "&Euml;" => "Ë",
		   "&Igrave;" => "Ì",
		   "&Iacute;" => "Í",
		   "&Icirc;" => "Î",
		   "&Iuml;" => "Ï",
		   "&ETH;" => "Ð",
		   "&Ntilde;" => "Ñ",
		   "&Ograve;" => "Ò",
		   "&Oacute;" => "Ó",
		   "&Ocirc;" => "Ô",
		   "&Otilde;" => "Õ",
		   "&Ouml;" => "Ö",
		   "&Oslash;" => "Ø",
		   "&Ugrave;" => "Ù",
		   "&Uacute;" => "Ú",
		   "&Ucirc;" => "Û",
		   "&Uuml;" => "Ü",
		   "&Yacute;" => "Ý",
		   "&THORN;" => "Þ",
		   "&szlig;" => "ß",
		   "&agrave;" => "à",
		   "&aacute;" => "á",
		   "&acirc;" => "â",
		   "&atilde;" => "ã",
		   "&auml;" => "ä",
		   "&aring;" => "å",
		   "&aelig;" => "æ",
		   "&ccedil;" => "ç",
		   "&egrave;" => "è",
		   "&eacute;" => "é",
		   "&ecirc;" => "ê",
		   "&euml;" => "ë",
		   "&igrave;" => "ì",
		   "&iacute;" => "í",
		   "&icirc;" => "î",
		   "&iuml;" => "ï",
		   "&eth;" => "ð",
		   "&ntilde;" => "ñ",
		   "&ograve;" => "ò",
		   "&oacute;" => "ó",
		   "&ocirc;" => "ô",
		   "&otilde;" => "õ",
		   "&ouml;" => "ö",
		   "&oslash;" => "ø",
		   "&ugrave;" => "ù",
		   "&uacute;" => "ú",
		   "&ucirc;" => "û",
		   "&uuml;" => "ü",
		   "&yacute;" => "ý",
		   "&thorn;" => "þ",
		   "&yuml;" => "ÿ",
		   "&laquo;" => "«",
		   "&raquo;" => "»",
		   "&euro;" => "€",
		   "&#149;" => "•",
		   "&#8217" => "’",
		   "&#8216" => "‘",
		   "&#160" => " ",
		   "&#8230;" => "...",
		   "&#8220;" => "“",
		   "&#8221;" => "”",
		   "&#8222;" => "„",
		   "&deg;" => "°");
  
  while(my($entity, $char) = each(%entity2char)){
    $string =~ s/$entity/$char/g;
  }
  return $string;
}
