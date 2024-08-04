import 'dart:io';
import 'package:args/args.dart';
import 'package:supadart/config_init.dart';
import 'package:yaml/yaml.dart';
import 'package:supadart/generator/generator.dart';
import 'package:supadart/generator/swagger.dart';

const String version = 'v1.3.8';
const String red = '\x1B[31m'; // Red text
const String green = '\x1B[32m'; // Green text
const String blue = '\x1B[34m'; // Blue text
const String reset = '\x1B[0m'; // Reset to default color

void main(List<String> arguments) async {
  final defaultConfigFile = 'supadart.yaml';
  final parser = ArgParser()
    ..addOption('config',
        abbr: 'c',
        defaultsTo: defaultConfigFile,
        help: 'Path to config file of .yaml')
    ..addFlag('help',
        abbr: 'h', negatable: false, help: 'Show usage information')
    ..addFlag('version', abbr: 'v', negatable: false, help: version);

  final results = parser.parse(arguments);

  if (results['help']) {
    print('Usage: dart script.dart [options]');
    print(parser.usage);
    exit(0);
  }

  if (results['version']) {
    print(version);
    exit(0);
  }

  String url;
  String anonKey;
  bool isDart;
  String output;
  YamlMap? mappings;

  final configPath = results['config'] ?? defaultConfigFile;
  if (!File(configPath).existsSync()) {
    print('$configPath file not found, do you want to create one? (yes/no)');
    final userInput = stdin.readLineSync();
    if (userInput != null &&
        (userInput.toLowerCase() == 'yes' || userInput.toLowerCase() == 'y')) {
      await configFileInit(configPath);
    } else {
      print('File not created.');
      exit(0);
    }
  }

  final configFile = File(configPath);
  final configContent = await configFile.readAsString();
  final config = loadYaml(configContent);

  url = config['supabase_url'] ?? '';
  anonKey = config['supabase_anon_key'] ?? '';
  if (url.isEmpty || anonKey.isEmpty) {
    print("Please provide supabase_url and supabase_anon_key in .yaml file");
    exit(1);
  }

  isDart = config['dart'] ?? false;
  output = config['output'] ?? './lib/models/';
  mappings = config['mappings'];

  print('URL: $url');
  print('ANON KEY: $anonKey');
  print('Output: $output');
  print('Dart: $isDart');
  print('Mappings: $mappings');
  print('=' * 50);

  final databaseSwagger = await fetchDatabaseSwagger(url, anonKey);
  if (databaseSwagger == null) {
    print('Failed to fetch database');
    exit(1);
  }

  final files = generateModelFiles(databaseSwagger, isDart, mappings);
  await generateAndFormatFiles(files, output);

  print('\n$green 🎉 Done! $reset');
}

Future<void> generateAndFormatFiles(
    List<GeneratedFile> files, String folderPath) async {
  await Future.wait(files.map((file) async {
    final filePath = folderPath + file.fileName;
    final fileToGenerate = File(filePath);

    // Create file if it doesn't exist else overwrite it
    await fileToGenerate.create(recursive: true);
    await fileToGenerate.writeAsString(file.fileContent);

    // Format the file
    await formatCode(filePath);
    stdout.write('$green 🎯 Generated: $filePath $reset');
  }));
}

Future<void> formatCode(String filePath) async {
  try {
    ProcessResult result = await Process.run('dart', ['format', filePath]);
    if (result.exitCode != 0) {
      stdout.write('$red Failed to Format $filePath $reset\n');
    } else {
      stdout.write('$blue Formatted $reset\n');
    }
  } catch (e) {
    print('Failed to format code: $e');
  }
}
