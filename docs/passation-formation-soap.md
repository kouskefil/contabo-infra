# Dossier de passation — formation SOAP

À déposer dans un nouveau projet Claude consacré à l'apprentissage de SOAP. Ce projet-là ne verra pas
les conversations du projet d'infrastructure : ce document contient tout le contexte utile.

## Mon objectif

Maîtriser SOAP en partant de mon propre service, déjà en ligne. Je suis développeur Java backend senior
(Spring Boot, REST), mais **XSD, WSDL et WS-Security sont nouveaux pour moi**. Lors du déploiement,
j'ai exécuté les commandes sans comprendre le fond : je veux maintenant comprendre chaque notion.

## Consignes proposées pour le projet

> Tu es mon formateur SOAP. Je suis développeur Java senior, à l'aise en REST et Spring Boot, débutant
> en SOAP. Appuie-toi sur mon service `clients-ws` décrit dans le dossier de passation. Avance une
> notion à la fois : explique-la simplement, montre-la dans MES fichiers, compare-la à son équivalent
> REST, puis propose-moi un petit exercice et attends ma réponse avant de continuer. Vérifie ma
> compréhension par des questions. Pas de bloc de commandes à exécuter sans explication.

## Le service

| Élément | Valeur |
|---|---|
| Adresse | `https://api.kouskefil.tech/ws` (POST) |
| WSDL | `https://api.kouskefil.tech/ws/clients.wsdl` (public) |
| Namespace | `http://kouskefil.tech/ws/clients/v1` |
| Opérations | `getClient`, `createClient`, `searchClients` |
| Protocole | SOAP 1.1, style document/literal |
| Sécurité | WS-Security UsernameToken (PasswordDigest), compte `partenaire`, anti-rejeu |
| Pile | Spring Boot 4.1.1, Spring Web Services 5.0.2, Apache WSS4J 4.0.1, Java 21, JAXB, PostgreSQL |
| Approche | contract-first : le XSD est écrit à la main, le reste en découle |
| Code | dépôt GitHub `kouskefil/clients-ws` |

Ce qui découle du XSD :
- les **classes Java** (`tech.kouskefil.clients.ws.schema.*`), générées à la compilation par `jaxb2-maven-plugin` ;
- le **WSDL**, généré à l'exécution par `DefaultWsdl11Definition` ;
- la **validation** de chaque requête et réponse (`PayloadValidatingInterceptor`).

## Fichiers à joindre au projet

Depuis le dépôt `clients-ws` :
- `src/main/resources/xsd/clients.xsd` (reproduit ci-dessous)
- `src/main/java/tech/kouskefil/clients/config/WebServiceConfig.java`
- `src/main/java/tech/kouskefil/clients/ws/ClientEndpoint.java`
- `src/main/java/tech/kouskefil/clients/domain/ClientIntrouvableException.java`
- `pom.xml`
- `samples/call.py` (client de test, qui construit l'en-tête WS-Security)

Et le WSDL réel, à télécharger :

```bash
curl -s https://api.kouskefil.tech/ws/clients.wsdl > clients.wsdl
```

Ne jamais déposer le mot de passe WS-Security dans le projet.

## Le contrat (XSD)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!--
  Contrat du service Clients, version 1.
  Ce fichier est la SOURCE DE VÉRITÉ : le WSDL et les classes Java en sont dérivés.
  Convention Spring-WS : un élément xxxRequest + un élément xxxResponse = une opération "xxx".
-->
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
           xmlns:tns="http://kouskefil.tech/ws/clients/v1"
           targetNamespace="http://kouskefil.tech/ws/clients/v1"
           elementFormDefault="qualified"
           version="1.0">

  <!-- Types simples : les contraintes sont dans le contrat, pas seulement dans le code -->
  <xs:simpleType name="NomType">
    <xs:restriction base="xs:string">
      <xs:minLength value="1"/>
      <xs:maxLength value="100"/>
    </xs:restriction>
  </xs:simpleType>

  <xs:simpleType name="EmailType">
    <xs:restriction base="xs:string">
      <xs:maxLength value="254"/>
      <xs:pattern value="[^@\s]+@[^@\s]+\.[^@\s]+"/>
    </xs:restriction>
  </xs:simpleType>

  <xs:simpleType name="LimiteType">
    <xs:restriction base="xs:int">
      <xs:minInclusive value="1"/>
      <xs:maxInclusive value="100"/>
    </xs:restriction>
  </xs:simpleType>

  <!-- Type métier -->
  <xs:complexType name="Client">
    <xs:sequence>
      <xs:element name="id" type="xs:long"/>
      <xs:element name="nom" type="tns:NomType"/>
      <xs:element name="email" type="tns:EmailType"/>
      <xs:element name="creeLe" type="xs:dateTime"/>
    </xs:sequence>
  </xs:complexType>

  <!-- Opération getClient -->
  <xs:element name="getClientRequest">
    <xs:complexType>
      <xs:sequence>
        <xs:element name="id" type="xs:long"/>
      </xs:sequence>
    </xs:complexType>
  </xs:element>
  <xs:element name="getClientResponse">
    <xs:complexType>
      <xs:sequence>
        <xs:element name="client" type="tns:Client"/>
      </xs:sequence>
    </xs:complexType>
  </xs:element>

  <!-- Opération createClient -->
  <xs:element name="createClientRequest">
    <xs:complexType>
      <xs:sequence>
        <xs:element name="nom" type="tns:NomType"/>
        <xs:element name="email" type="tns:EmailType"/>
      </xs:sequence>
    </xs:complexType>
  </xs:element>
  <xs:element name="createClientResponse">
    <xs:complexType>
      <xs:sequence>
        <xs:element name="client" type="tns:Client"/>
      </xs:sequence>
    </xs:complexType>
  </xs:element>

  <!-- Opération searchClients -->
  <xs:element name="searchClientsRequest">
    <xs:complexType>
      <xs:sequence>
        <xs:element name="nom" type="tns:NomType" minOccurs="0"/>
        <xs:element name="limite" type="tns:LimiteType" minOccurs="0"/>
      </xs:sequence>
    </xs:complexType>
  </xs:element>
  <xs:element name="searchClientsResponse">
    <xs:complexType>
      <xs:sequence>
        <xs:element name="client" type="tns:Client" minOccurs="0" maxOccurs="unbounded"/>
      </xs:sequence>
    </xs:complexType>
  </xs:element>
</xs:schema>
```

## Messages réels du service

### Requête `createClient` (sans l'en-tête de sécurité)

```xml
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:cli="http://kouskefil.tech/ws/clients/v1">
  <soapenv:Header/>
  <soapenv:Body>
    <cli:createClientRequest>
      <cli:nom>Ada Lovelace</cli:nom>
      <cli:email>ada@example.com</cli:email>
    </cli:createClientRequest>
  </soapenv:Body>
</soapenv:Envelope>
```

### Réponse (HTTP 200)

```xml
<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
  <SOAP-ENV:Header/>
  <SOAP-ENV:Body>
    <ns2:createClientResponse xmlns:ns2="http://kouskefil.tech/ws/clients/v1">
      <ns2:client>
        <ns2:id>1</ns2:id>
        <ns2:nom>Ada Lovelace</ns2:nom>
        <ns2:email>ada@example.com</ns2:email>
        <ns2:creeLe>2026-11-14T17:57:50.819Z</ns2:creeLe>
      </ns2:client>
    </ns2:createClientResponse>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
```

### L'en-tête WS-Security envoyé par le client

```xml
<soapenv:Header>
  <wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"
                 xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"
                 soapenv:mustUnderstand="1">
    <wsse:UsernameToken>
      <wsse:Username>partenaire</wsse:Username>
      <wsse:Password Type="...#PasswordDigest">(empreinte en Base64)</wsse:Password>
      <wsse:Nonce EncodingType="...#Base64Binary">(valeur aléatoire en Base64)</wsse:Nonce>
      <wsu:Created>2026-11-14T18:11:18.880Z</wsu:Created>
    </wsse:UsernameToken>
  </wsse:Security>
</soapenv:Header>
```

Empreinte = Base64( SHA-1( nonce + created + mot de passe ) ).

### Les erreurs (SOAP Faults, toujours en HTTP 500)

| Situation | `faultcode` | `faultstring` | Origine |
|---|---|---|---|
| Client inexistant | `Client` | `Client introuvable : id=999999` | code métier (`@SoapFault`) |
| Email déjà utilisé | `Client` | `Un client existe déjà avec l'email ada@example.com` | code métier |
| Email mal formé | `Client` | `Validation error`, avec un bloc `<detail>` (`cvc-pattern-valid…`) | validation XSD, avant le code |
| Pas d'en-tête de sécurité | `Client` | `No WS-Security header found` | WS-Security |
| Mauvais mot de passe | `Client` | `The security token could not be authenticated or authorized` | WS-Security |
| Même message renvoyé | `Client` | `…"A replay attack has been detected"` | cache anti-rejeu |

Exemple de Fault de validation :

```xml
<SOAP-ENV:Fault>
  <faultcode>SOAP-ENV:Client</faultcode>
  <faultstring xml:lang="en">Validation error</faultstring>
  <detail>
    <spring-ws:ValidationError xmlns:spring-ws="http://springframework.org/spring-ws">cvc-pattern-valid: Value 'pas-un-email' is not facet-valid with respect to pattern '[^@\s]+@[^@\s]+\.[^@\s]+' for type 'EmailType'.</spring-ws:ValidationError>
  </detail>
</SOAP-ENV:Fault>
```

## Ce que j'ai observé sans le comprendre

- Le client envoie le préfixe `cli:`, le serveur répond avec `ns2:`.
- Toutes les opérations partagent la même URL `/ws` : le routage se fait sur le contenu du message.
- Une erreur du client renvoie HTTP 500, pas 400 ou 404.
- Un email invalide est refusé sans que mon code Java soit appelé.
- La sécurité est vérifiée avant la validation du contenu.
- `xml:lang="en"` apparaît sur des messages d'erreur en français.

## Parcours de formation proposé

1. **XML et namespaces** : éléments, attributs, préfixes, pourquoi `cli:` et `ns2:` désignent la même chose.
2. **XSD** : types simples et complexes, restrictions, `minOccurs`/`maxOccurs`, lire `clients.xsd` ligne par ligne, puis y ajouter un champ.
3. **L'enveloppe SOAP** : Envelope, Header, Body ; SOAP 1.1 et 1.2 ; comparaison avec une requête REST.
4. **WSDL** : types, messages, portType, binding, service ; lire `clients.wsdl` ; comprendre comment il est déduit du XSD.
5. **Contract-first et contract-last** : pourquoi écrire le XSD d'abord ; les classes JAXB générées.
6. **Spring Web Services** : `@Endpoint`, `@PayloadRoot`, les intercepteurs, le trajet d'un message dans `MessageDispatcherServlet`.
7. **SOAP Faults** : `faultcode`, `faultstring`, `detail` ; Faults personnalisés ; pourquoi HTTP 500.
8. **WS-Security** : UsernameToken (texte et digest), nonce, horodatage, rejeu ; puis signature et chiffrement X.509.
9. **Outils** : SoapUI, lecture d'un message brut, `curl`.
10. **Tests** : `MockWebServiceClient` côté serveur.
11. **Écrire un client** : `WebServiceTemplate`, génération de classes depuis un WSDL tiers.
12. **Sujets avancés** : MTOM (pièces jointes), WS-Addressing, versionnement d'un contrat (v1 vers v2).

Restent à faire sur le service lui-même, comme exercices : des tests automatisés, des Faults avec un
`detail` typé, un message d'erreur en français (`xml:lang="fr"`), et un client Java.
