// Erorile trimise de server și de motoarele de joc (vezi `GameError`).
// Fiecare intrare: cheie → (română, engleză).

const Map<String, (String, String)> errorStrings = {
  'err.unknown': ('Eroare necunoscută.', 'Unknown error.'),
  'err.roomFull': ('Camera este plină (maxim {max} jucători).', 'The room is full (max {max} players).'),
  'err.chatFull': ('Camera de chat e plină (maxim {max} persoane).', 'The chat room is full (max {max} people).'),
  'err.chatNoActions': ('Camera de chat nu are acțiuni de joc.', 'The chat room has no game actions.'),
  'err.cannotStart': (
    'Nu se poate porni jocul (minim {min}, maxim {max} jucători).',
    'The game cannot start (min {min}, max {max} players).'
  ),
  'err.playersRange': ('Sunt necesari {min}-{max} jucători.', '{min}-{max} players are required.'),
  'err.playersExact': ('Sunt necesari exact {n} jucători.', 'Exactly {n} players are required.'),
  'err.alreadyStarted': ('Jocul e deja în desfășurare.', 'The game is already in progress.'),
  'err.unknownPlayer': ('Jucător necunoscut.', 'Unknown player.'),
  'err.unknownAction': ('Acțiune necunoscută.', 'Unknown action.'),
  'err.invalidAction': ('Acțiune invalidă.', 'Invalid action.'),
  'err.noCardsToPlay': ('Nicio carte de jucat.', 'No card to play.'),
  'err.sameRankOnly': (
    'Poți juca simultan doar cărți de aceeași valoare.',
    'You can only play cards of the same rank together.'
  ),
  'err.invalidMove': ('Mutare invalidă.', 'Invalid move.'),
  'err.mustChooseColor': ('Trebuie aleasă o culoare pentru această carte.', 'You must choose a color for this card.'),
  'err.notYourCard': ('Nu ai această carte.', 'You don\'t have this card.'),
  'err.gameNotActive': ('Jocul nu este activ.', 'The game is not active.'),
  'err.notYourTurn': ('Nu este rândul tău.', 'It\'s not your turn.'),
  'err.deckEmpty': ('Nu mai sunt cărți disponibile în pachet.', 'There are no more cards in the deck.'),
  'err.notPlayingPhase': ('Nu este faza de joc.', 'This is not the playing phase.'),
  'err.mustFollowSuit': ('Trebuie să joci culoarea cerută dacă o ai.', 'You must follow suit if you can.'),

  // Meniu / comenzi
  'err.menu.tableRequired': (
    'Introdu numărul mesei înainte să trimiți comanda.',
    'Enter your table number before sending the order.'
  ),
  'err.menu.tableTooLong': ('Numărul mesei e prea lung.', 'The table number is too long.'),
  'err.menu.tooManyOpen': (
    'Ai deja {max} comenzi în așteptare — așteaptă să fie pregătite.',
    'You already have {max} pending orders — wait for them to be prepared.'
  ),
  'err.menu.tooManyLines': ('Comanda are prea multe produse.', 'The order has too many items.'),
  'err.menu.maxQuantity': (
    'Maxim {max} bucăți dintr-un produs pe comandă.',
    'At most {max} of one item per order.'
  ),
  'err.menu.empty': (
    'Comanda e goală — alege cel puțin un produs disponibil.',
    'The order is empty — choose at least one available item.'
  ),

  // Poker
  'err.poker.mustCall': (
    'Nu poți da check — trebuie să egalezi {amount}.',
    'You can\'t check — you must call {amount}.'
  ),
  'err.poker.nothingToCall': ('Nu mai ai nimic de egalat — dă check.', 'Nothing to call — check instead.'),
  'err.poker.minRaise': ('Raise minim: {amount}.', 'Minimum raise: {amount}.'),

  // Rentz
  'err.rent.notChoosingPhase': ('Nu este faza de alegere a categoriei.', 'This is not the category selection phase.'),
  'err.rent.notYourChoice': ('Nu este rândul tău să alegi.', 'It\'s not your turn to choose.'),
  'err.rent.unknownCategory': ('Categorie necunoscută.', 'Unknown category.'),
  'err.rent.categoryUsed': ('Categoria a fost deja jucată.', 'This category has already been played.'),
  'err.rent.invalidMove': (
    'Mutare invalidă — nu se leagă de nicio secvență deschisă.',
    'Invalid move — it doesn\'t connect to any open sequence.'
  ),

  // Șeptică
  'err.septica.mustMatch': (
    'Trebuie o carte cu numărul din luptă sau o tăietură, ca să continui.',
    'You need a card of the contested rank or a cut to continue.'
  ),
  'err.septica.cannotConcede': ('Nu poți renunța acum.', 'You can\'t give up now.'),
  'err.septica.onlyLeaderConcedes': (
    'Doar conducătorul poate renunța la luptă.',
    'Only the leader can give up the fight.'
  ),

  // Uno
  'err.uno.alreadyDrew': ('Ai tras deja o carte tura asta.', 'You already drew a card this turn.'),
  'err.uno.mustDrawFirst': (
    'Trebuie să tragi o carte înainte să treci tura.',
    'You must draw a card before passing.'
  ),

  // Război
  'err.war.alreadyFlipped': (
    'Ai întors deja cartea, aștepți adversarul.',
    'You already flipped your card — waiting for your opponent.'
  ),

  // Whist
  'err.whist.notBidding': ('Nu este faza de licitație.', 'This is not the bidding phase.'),
  'err.whist.notYourBid': ('Nu este rândul tău să licitezi.', 'It\'s not your turn to bid.'),
  'err.whist.bidRange': ('Licitația trebuie să fie între 0 și {max}.', 'Your bid must be between 0 and {max}.'),
  'err.whist.forbiddenBid': (
    'Nu poți licita {amount} — suma licitațiilor ar fi exact {total}.',
    'You can\'t bid {amount} — the bids would add up to exactly {total}.'
  ),

  // Cameră / server
  'err.kicked': (
    'Ai fost dat afară din această cameră de organizator.',
    'The organizer removed you from this room.'
  ),
  'err.gameInProgressJoin': (
    'Jocul a început deja — poți intra după ce se termină partida.',
    'The game has already started — you can join once it ends.'
  ),
  'err.onlyHostStarts': (
    'Doar cel care a creat camera poate începe jocul.',
    'Only the person who created the room can start the game.'
  ),
  'err.serverFull': ('Serverul e plin — încearcă puțin mai târziu.', 'The server is full — try again in a moment.'),
  'err.chatTooLong': ('Mesajul e prea lung (maxim {max} caractere).', 'The message is too long (max {max} characters).'),
  'err.muted': ('Chat-ul tău a fost oprit de organizator.', 'The organizer has muted your chat.'),
  'err.organizerOnly': ('Doar organizatorul poate monitoriza camere.', 'Only the organizer can monitor rooms.'),
  'err.roomNotFound': ('Nu există nicio cameră cu acest cod.', 'There is no room with this code.'),
  'err.invalidCreate': ('Cerere de creare a camerei invalidă.', 'Invalid room creation request.'),
  'err.activityUnavailable': ('Activitatea nu e disponibilă în seara asta.', 'This activity isn\'t available tonight.'),
  'err.tooManyRooms': (
    'Sunt prea multe camere deschise — alătură-te uneia existente.',
    'There are too many open rooms — join an existing one.'
  ),
  'err.blocked': ('Ai fost blocat de organizator.', 'You have been blocked by the organizer.'),
  'err.invalidJoin': ('Cerere de alăturare invalidă.', 'Invalid join request.'),
  'err.wrongGame': ('Camera aceasta găzduiește alt joc.', 'This room is hosting a different game.'),

  // Conexiune (client)
  'err.connInactive': ('Conexiune inactivă.', 'Connection inactive.'),
  'err.connClosed': ('Conexiune închisă.', 'Connection closed.'),
  'err.connLost': ('Conexiune pierdută — nu m-am putut reconecta.', 'Connection lost — could not reconnect.'),
  'err.replaced': (
    'Ai intrat în cameră de pe altă conexiune — aceasta a fost închisă.',
    'You joined the room from another connection — this one was closed.'
  ),
  'err.serverStart': ('Serverul nu a putut porni.', 'The server could not start.'),
};
