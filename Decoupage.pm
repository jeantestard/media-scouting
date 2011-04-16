package Decoupage;

#!/usr/bin/perl -w

## Script de découpage des journeaux du corpus.
## Le script extrait d'une page web le contenu de l'article (i.e. sans les menus de navigation, pubs, etc.) et si possible le titre et la date de publication

=head1 NAME

Decoupage  : operations de decoupage des articles pour corpus


=head1 SYNOPSIS

use Decoupage;
init("www.lemonde.fr", $fichier) || die $!;
$encodage = getEncodage();
$titre = getTitre(txt);
$date = getDate(txt);
$contenu_html = getContenu(html);
$contenu_txt = getContenu(txt);


=head1 DESCRIPTION

Le module Decoupage s'appuie sur le module HTML::TreeBuilder pour parser le fichier html a decouper.
Chaque element a decouper (titre, date, contenu) est delimite par une balise html ou un attribut html.
Ces informations sont propres a chaque journal vise. Ces informations doivent etre ajoutees a une structure de donnees de type table de hachage
qui recoit en cle l'url du journal et en cle une reference vers un tableau anonyme comportant les informations.

=cut


use strict;
use HTML::TreeBuilder;
use Data::Dumper;
use Carp;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(&init &getEncodage &getTitre &getDate &getContenu);

my $fichier; #le nom du fichier à traiter
my $journal; #le nom du journal
my %tabh;

=head2 FUNCTION init()

La fonction init("url_journal", $nom_de_fichier) doit etre appellee en premier lieu. Elle verifie que les informations necessaire au decoupage existent pour le journal vise et renvoie vrai si oui et faux sinon

=cut

sub init {
carp("erreur nb arguments dans appel init") unless (@_ == 2);

$journal = $_[0];
$fichier = $_[1];

carp("Fichier $fichier introuvable") unless (-f $fichier);

## journal => [contenu, titre, date]
%tabh = (
	 "sankei.jp.msn.com" => [{'class' => '_LSUCS'}, {'id' => '__r_article_title__'}, {'id' => '__r_article_date__'}],
	 "mainichi.jp" => [{'class'=>'NewsBody'}, {'class'=>'NewsTitle'}, {'class'=>'CreditTop'}],
	 "www.nikkei.co.jp" => [{'class' => 'article-cap'}, {'class' => 'topNews-tt13'}],
	 "www.asahi.com" => [{'div' => 'HeadLine'}],
	 "www.yomiuri.co.jp" => [{'class' => 'article-def'}],
	 "www.morgenpost.de" => [{'class' => 'articleContent'}, {'class', 'articleTeaser'}, {'class' => 'articleDate'}],
	 "www.spiegel.de" => [{'id' => 'spArticleColumn'}, "h1", {'id' => 'spShortDate'}],
	 "www.welt.de" => [{'class' => 'articleBox clear'}],
	 "www.handelsblatt.com" => [{'class' => 'text'}, {'class' => 'headline'}, {'class' => 'date'}],
	 "sueddeutsche.de" => ['p', {'class' => 'headers nopages'}],
	 "www.lemonde.fr" => [{'class' => 'mainText'}, {'id' => 'mainTitle'}, {'class' => 'dateline'}],
	 "www.lepoint.fr" => [{'class' => 'texte'}, 'title', {'class' => 'heure'}],
	 "www.lesechos.fr" => [{'id' => 'article'}, 'title', {'class' => 'date-maj'}],
	 "www.humanite.fr" => [{'class' => 'texte'}, 'title', ],
	 "www.la-croix.com" => [{'id' => 'montexte'}, {'class' => 'titre_art'}, {'class' => 'art_date'}],
	 "online.wsj.com" => [{'id' => 'article_story_body'}, 'h1', {'class' => 'dateStamp'}],
	 "www.usatoday.com" => [{'class' => 'inside-copy'}, '', {'class' => 'inside-head'}],
	 "www.time.com" => [{'class' => 'copy'}, {'class' => 'entryTitle'}, {'class' => 'entryDate'}],
	 "www.nytimes.com" => [{'id' => 'articlebody'}, '', {'class' => 'timestamp'}],
	 "www.ft.com" => [{'id' => 'floating-target'}, {'class' => 'ft-story-header'}, {'class' => 'ft-story-header'}],
	 "gazeta.ru"=> [{'class' => 'article'},{'class' => 'mb03 shift_left'},{'class' => 'cap1 mb09'}],
	 "kommersant.ru" => [{'id' => 'ctl00_ContentPlaceHolderStyle_LabelText'},{'id' => 'ctl00_ContentPlaceHolderStyle_LabelTitle'},{'class' => 'freelink-c'}],
	 "lgz.ru" => ['p',{'class' => 'titlebigblue'},{'class' => 'author'}],
	 "novayagazeta.ru" => ['div',{'class' => 'main'},],
	 "newizv.ru" => [{'class' => '_ga1_on_'},'h1',],
	 "ng.ru" => [ {'class' => 'article-body'},'h1',{'id' => 'author'}],
	 "www.ferghana.ru" => [{'id' => 'article'},'h2',{'id' => 'authors'}],
	 "www.alwasatnews.com" => [{'id' => 'body_content'}, 'h1', {'class' => 'tab-text'}], # (problème d'encodage : windows 1256)
	 "www.alqabas.com.kw" => [{'id' => 'divDetails'}, {'class' => 'articleTitle'}, {'id' => 'ctl00_PageContentPlaceHolder_lblDate'}], # (problème d'encodage : windows 1256)
	 "www.aawsat.com" => [{'class' => 'storybold'}, {'class' => 'headline6'}, {'class' => 'headline2'}], # (problème d'encodage : windows 1256)
	 "www.aljazeera.net" => [{'id' => 'tdStoryBody'}, {'id' => 'tdMainHeader'}, {'class' => 'tdDateTime'}],
	 "www.alaswaq.net" => [{'class' => 'txt_article_v2'}, {'class' => 'txt_title_large'}, {'class' => 'caption'}],
	 #journaux espagnols
	 "www.elpais.com" => [{'class' => 'contenido_noticia'},{'class' => 'cabecera_noticia'},{'class' => 'firma'}],
	 "www.elmundo.es" => [{'id' => 'tamano'},{'class' => 'titular'},{'class' => 'fechayhora'}],
	 "www.lavanguardia.es" => [{'class' => 'text'},'h1',{'class' => 'caption'}],
	 "www.abc.es" => [{'class' => 'p'},{'id' => 'story-titulo'},{'class' => 'date'}],
	 "www.diariosur.es" => [{'class' => 'text'},{'class' => 'headline'},{'class' => 'date'}]
	);

# Erreur si le journal ne fait pas partie des journeaux connus
carp "$journal est inconnu" unless(exists($tabh{$journal}));
return 1;
}


=head2 FUNCTION getEncodage()

La fonction getEncodage() recupere l'encodage indique dans l'en-tete du fichier html

=cut

## getEncodage
## Renvoie l'encodage indiqué dans la page web passée en argument
sub getEncodage{
    my $tree = HTML::TreeBuilder->new();
    $tree->parse_file($fichier);

    my $encodage;

    my $tmp= $tree->find_by_attribute('http-equiv', 'Content-Type');
    $tmp= $tree->find_by_attribute('http-equiv', 'content-type') if(! defined($tmp));
    $tmp= $tree->find_by_attribute('http-equiv', 'Content-type') if(! defined($tmp));
    return undef unless defined($tmp);
    my $tmp_html = $tmp->as_HTML();
    if ($tmp_html =~ /.*charset=([a-zA-Z-0-9_]+)"/){
	$encodage = $1;
    }

    return $encodage;
}


=head2 FUNCTION getContenu()

La fonction getContenu("format") renvoie le contenu de l'element html entourant le contenu de l'article au format desire : html ou txt

=cut


## getContenu
## Récupère dans le fichier html le contenu de la balise 'contenu'
## Entrée : format désiré en retour (html ou txt)
sub getContenu{
    my $format = shift;

    carp("Le format indiqué n'est pas valide : html ou txt") unless($format eq "html" || $format eq "txt");

    my $ref_tab_balises = $tabh{$journal};

    my $tree = HTML::TreeBuilder->new();
    $tree->parse_file($fichier);

    my $result;

    
    #Cas d'un élément identifié par un attribut (ex : <div class="content">)
    if(ref($$ref_tab_balises[0]) eq 'HASH'){
	my @tmp = each(%{$$ref_tab_balises[0]});
	#my $contenu = $tree->find_by_attribute($tmp[0], $tmp[1]);
	my $contenu = $tree->look_down($tmp[0], $tmp[1]);
	return "" unless defined($contenu);
	$result = $contenu->as_HTML() if($format eq "html");
	$result = $contenu->as_text() if($format eq "txt");
    }
    #Cas d'un élément simple (ex : <p>)
    else{
	my $tmp = $ref_tab_balises->[0];
	my @content=$tree->find_by_tag_name($tmp);
	return "" unless (@content != 0);
	if($format eq "html"){
	    my @content_html = map($_->as_HTML(), @content);
	    $result = join("<br/>", @content_html);
	}
	elsif($format eq "txt"){
	    my @content_html = map($_->as_text(), @content);
	    $result = join("\n", @content_html);
	}
    }
    $tree = $tree->delete();
    return $result;
}


=head2 FUNCTION getTitre()

La fonction getTitre("format") renvoie le contenu de l'element html entourant le titre de l'article au format desire : html ou txt

=cut


## getTitre
## Récupère dans le fichier html le contenu de la balise 'titre'
## Entrée : liste des balises pour le journal visé (ref tableau),nom du fichier html, format désiré en retour (html ou txt)
sub getTitre{
  my $format = shift;
  carp("Le format indiqué n'est pas valide : html ou txt") unless($format eq "html" || $format eq "txt");
  
  my $ref_tab_balises = $tabh{$journal};
  
  my $tree = HTML::TreeBuilder->new();
  $tree->parse_file($fichier);
  
  my $result;


  #Cas d'un élément identifié par un attribut (ex : <div class="titre">)
  if(ref($$ref_tab_balises[1]) eq 'HASH'){
    my @tmp = each(%{$$ref_tab_balises[1]});
    my $contenu = $tree->find_by_attribute($tmp[0], $tmp[1]);
    return "" unless defined($contenu);
    my $contenu_format;
    $contenu_format = $contenu->as_HTML() if($format eq "html");
    $contenu_format = $contenu->as_text() if($format eq "txt");
    $result = $contenu_format;
  }
    #Cas d'un élément simple (ex : <p>)
    else{
	my $tmp = $ref_tab_balises->[1];
	my @content=$tree->find_by_tag_name($tmp);
	return "" unless (@content != 0);
	if($format eq "html"){
	  my @content_html = map($_->as_HTML(), @content);
	  $result = join("<br/>", @content_html);
	}
	elsif($format eq "txt"){
	  my @content_txt = map($_->as_text(), @content);
	  $result = join("\n", @content_txt);
	}
    }

    $tree = $tree->delete();
    return $result;

}


=head2 FUNCTION getDate()

La fonction getDate("format") renvoie le contenu de l'element html entourant la date de l'article au format desire : html ou txt

=cut


## getDate
## Récupère dans le fichier html le contenu de la balise 'date'
## Entrée : liste des balises pour le journal visé (ref tableau), nom du fichier html, format désiré en retour (html ou txt)
sub getDate{
  my $format = shift;
  carp("Le format indiqué n'est pas valide : html ou txt") unless($format eq "html" || $format eq "txt");
  
  my $ref_tab_balises = $tabh{$journal};

  my $tree = HTML::TreeBuilder->new();
  $tree->parse_file($fichier);
  
  my $result;
  
    
  #Cas d'un élément identifié par un attribut (ex : <div class="date">)
  if(ref($$ref_tab_balises[2]) eq 'HASH'){
    my @tmp = each(%{$$ref_tab_balises[2]});
    my $contenu = $tree->find_by_attribute($tmp[0], $tmp[1]);
    return "" unless defined($contenu);
    my $contenu_format;
    $contenu_format = $contenu->as_HTML() if($format eq "html");
    $contenu_format = $contenu->as_text() if($format eq "txt");
    $result = $contenu_format;
  }
    #Cas d'un élément simple (ex : <p>)
    else{
      my $tmp = $ref_tab_balises->[2];
      my @content=$tree->find_by_tag_name($tmp);
      return "" unless (@content != 0);
      if($format eq "html"){
	my @content_html = map($_->as_HTML(), @content);
	$result = join("<br/>", @content_html);
      }
      elsif($format eq "txt"){
	my @content_txt = map($_->as_text(), @content);
	$result = join("\n", @content_txt);
      }
    }
  
  $tree = $tree->delete();
  return $result;
}

return 1;
