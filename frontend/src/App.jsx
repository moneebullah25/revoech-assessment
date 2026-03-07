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

  return (
    <div>
      <h1>Fruit List</h1>
      <ul>
        {fruits.map(f => (
          <li key={f.name}>
            <strong>{f.name}</strong> — {f.color} — {f.in_season ? 'In Season' : 'Out of Season'}
          </li>
        ))}
      </ul>
    </div>
  )
}

export default App
