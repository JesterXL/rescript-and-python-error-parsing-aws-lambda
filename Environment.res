/*
    The Gitlab build process sets an enivornment variable for the Lambdas
    in QA and Prodution.
    For QA it's "qa". For Staging it's "staging". For Production it's "prod".
    We use this to determine what URL's to hit, what ElasticSearch index
    to use, and other things. This module acts like a class with static
    methods to read from Process and tell us what environment we're in.
    It's not pure in that it references Process as a global variable.
    Additionally, I've found that Ocaml/ReScript compiles in Node.Process
    as a module with types. I didn't know that when I coded this so
    just bound myself to the external process variable. Could change
    in the future, though, shouldn't hurt anything and more typesafe.
    
*/
@val external process: 'a = "process"

type environment
    = QA
    | Staging
    | Production

let environmentToString = environment =>
    switch environment {
    | QA => "qa"
    | Staging => "stage"
    | Production => "prod"
    }

let stringToEnvironment = str =>
    switch str {
    | "dev" => Some(QA)
    | "qa" => Some(QA)
    | "staging" => Some(Staging)
    | "prod" => Some(Production)
    | _ => None
    }

// TODO: make this safer
let getEnvironment = () => {
    if (process["env"]["NODE_ENV"] === "prod") {
        Production
    } else if (process["env"]["NODE_ENV"] === "staging") {
        Staging
    } else {
        QA
    }
}