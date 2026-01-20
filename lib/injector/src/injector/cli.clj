(ns injector.cli
  "Command-line interface for the dependency injector.

  This tool reads a deps.edn file, replaces specified dependencies with
  :local/root paths, and prints the modified deps.edn to stdout.

  Usage:
    injector --deps-file deps.edn org.myorg/my-lib /nix/store/xxx.jar

  The output can be redirected to create a new deps.edn file:
    injector --deps-file deps.edn my.lib /path/to/lib.jar > new-deps.edn"
  (:require [clojure.edn :as edn]
            [clojure.pprint :refer [pprint]]
            [clojure.string :as str]
            [clojure.tools.cli :refer [parse-opts]]
            [injector.core :refer [inject-dependencies]])
  (:gen-class))

;; Command-line option definitions for tools.cli
(def cli-opts
  [[nil "--deps-file DEPS_FILE" "Source deps.edn file."]])

(defn- usage
  "Generate a usage message combining any errors with the options summary."
  [summary errors]
  (->> (concat errors ["usage: injector [opts] [[<library> <jar-file>] ...]"
                       ""
                       "Options:"
                       summary])
       (str/join \newline)))

(defn -main
  "Entry point for the injector CLI.

  Parses command-line arguments, reads the deps.edn file, injects the
  specified local dependencies, and prints the result to stdout."
  [& args]
  (let [{:keys [options arguments errors summary]} (parse-opts args cli-opts)
        ;; Parse positional arguments as pairs: [lib-coord path lib-coord path ...]
        ;; Convert library coordinates from strings to symbols for deps.edn compatibility
        inj-deps (into {} (for [[k v] (partition 2 arguments)] [(symbol k) v]))]

    ;; Handle parsing errors
    (when (seq errors)
      (.println *err* (usage summary errors))
      (System/exit 1))

    ;; Validate required --deps-file option
    (when (not (contains? options :deps-file))
      (.println *err* (usage summary ["missing required argument: deps-file"]))
      (System/exit 1))

    ;; Read deps.edn, inject dependencies, and print result
    (let [deps (-> options :deps-file (slurp) (edn/read-string))]
      (pprint (inject-dependencies deps inj-deps)))

    (System/exit 0)))
