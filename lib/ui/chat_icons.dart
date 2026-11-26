import 'package:flutter/material.dart';

/// **The icons a reply may name, and the reason the list is finite.**
///
/// Flutter has no way to look an `IconData` up by name at run time: `Icons.wine_bar` is a constant and the name it
/// was written with is gone by the time the tree is built. So a reply that says `:wine:` needs a table, and the table
/// is this file.
///
/// **Curated rather than the whole Material set.** Two thousand names would be a dictionary nobody could keep, and a
/// model handed one would reach for `:kitchen:` to mean "a drink". These are the things this application is actually
/// about -- what is in a glass, what it cost, when it was poured -- and a name outside the table prints as the
/// `:name:` the reply wrote, which is a visible mistake rather than an invisible one.
///
/// Every name here is a Material icon that exists in the SDK this project pins. Adding one is a one-line change and
/// the analyzer checks it, which is the property that makes a hand-kept list safe.
const Map<String, IconData> chatIcons = <String, IconData>{
  // What is in the glass.
  'wine': Icons.wine_bar,
  'cocktail': Icons.local_bar,
  'bottle': Icons.liquor,
  'beer': Icons.sports_bar,
  'coffee': Icons.coffee,
  'cup': Icons.emoji_food_beverage,
  'glass': Icons.local_drink,
  'night': Icons.nightlife,
  'water': Icons.water_drop,
  'ice': Icons.ac_unit,
  'fire': Icons.local_fire_department,
  'leaf': Icons.spa,
  'grain': Icons.grain,
  'food': Icons.restaurant,
  'kitchen': Icons.kitchen,
  'cake': Icons.cake,

  // What it cost, and which way it went.
  'money': Icons.payments,
  'paid': Icons.paid,
  'receipt': Icons.receipt_long,
  'up': Icons.trending_up,
  'down': Icons.trending_down,
  'chart': Icons.show_chart,
  'bars': Icons.bar_chart,
  'pie': Icons.pie_chart,
  'insight': Icons.insights,

  // The measuring and the waiting.
  'scale': Icons.scale,
  'timer': Icons.timer,
  'clock': Icons.schedule,
  'heat': Icons.thermostat,
  'bolt': Icons.bolt,

  // Marks a sentence can carry.
  'heart': Icons.favorite,
  'star': Icons.star,
  'done': Icons.check_circle,
  'warn': Icons.warning,
  'info': Icons.info,
  'idea': Icons.lightbulb,

  // The doors into the rest of the application.
  'barcode': Icons.qr_code_scanner,
  'photo': Icons.photo_camera,
  'book': Icons.menu_book,
  'science': Icons.science,
};

/// The icon a reply asked for, or null when the name is not one of ours.
IconData? chatIcon(String name) => chatIcons[name];

/// The names, sorted, for the prompt to quote.
///
/// **Read off the table rather than typed a second time.** A prompt listing names by hand and a table holding them
/// by hand disagree the first time one of them is edited, and the disagreement shows up as an icon that never
/// appears with nothing in any log to say why.
List<String> get chatIconNames => chatIcons.keys.toList()..sort();
