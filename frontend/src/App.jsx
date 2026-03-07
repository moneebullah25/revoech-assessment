import { useState, useEffect } from 'react'

const API = 'http://localhost:8000'

function App() {
  const [fruits, setFruits] = useState([])

  useEffect(() => {
    fetch(`${API}/fruit`)
      .then(r => r.json())
      .then(setFruits)
      .catch(console.error)
  }, [])

  return <div><h1>Fruit List</h1><p>{fruits.length} items loaded</p></div>
}

export default App
