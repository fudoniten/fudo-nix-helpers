(ns build-injector.core
  (:require [clojure.edn :as edn]))

(defn inject-build-namespace [m ns]
  (assoc-in m [:aliases :build :ns-default] ns))

(defn inject-build-dependencies [deps inj-deps]
  (update-in deps [:aliases :build :deps]
             (fn [existing-deps]
               (merge existing-deps
                      (into {}
                            (map (fn [[dep ver]]
                                   {(symbol dep) { :mvn/version ver }}))
                            inj-deps)))))
